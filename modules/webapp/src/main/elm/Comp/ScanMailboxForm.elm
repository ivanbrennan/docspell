module Comp.ScanMailboxForm exposing
    ( Action(..)
    , Model
    , Msg
    , init
    , initWith
    , update
    , view
    )

import Api
import Api.Model.BasicResult exposing (BasicResult)
import Api.Model.ImapSettingsList exposing (ImapSettingsList)
import Api.Model.ScanMailboxSettings exposing (ScanMailboxSettings)
import Comp.CalEventInput
import Comp.Dropdown
import Comp.IntField
import Comp.StringListInput
import Comp.YesNoDimmer
import Data.CalEvent exposing (CalEvent)
import Data.Direction exposing (Direction(..))
import Data.Flags exposing (Flags)
import Data.Validated exposing (Validated(..))
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onCheck, onClick, onInput)
import Http
import Util.Http
import Util.List
import Util.Maybe
import Util.Update


type alias Model =
    { settings : ScanMailboxSettings
    , connectionModel : Comp.Dropdown.Model String
    , enabled : Bool
    , deleteMail : Bool
    , receivedHours : Maybe Int
    , receivedHoursModel : Comp.IntField.Model
    , targetFolder : Maybe String
    , foldersModel : Comp.StringListInput.Model
    , folders : List String
    , direction : Maybe Direction
    , schedule : Validated CalEvent
    , scheduleModel : Comp.CalEventInput.Model
    , formMsg : Maybe BasicResult
    , loading : Int
    , yesNoDelete : Comp.YesNoDimmer.Model
    }


type Action
    = SubmitAction ScanMailboxSettings
    | StartOnceAction ScanMailboxSettings
    | CancelAction
    | DeleteAction String
    | NoAction


type Msg
    = Submit
    | Cancel
    | RequestDelete
    | ConnMsg (Comp.Dropdown.Msg String)
    | ConnResp (Result Http.Error ImapSettingsList)
    | ToggleEnabled
    | ToggleDeleteMail
    | CalEventMsg Comp.CalEventInput.Msg
    | StartOnce
    | ReceivedHoursMsg Comp.IntField.Msg
    | SetTargetFolder String
    | FoldersMsg Comp.StringListInput.Msg
    | DirectionMsg (Maybe Direction)
    | YesNoDeleteMsg Comp.YesNoDimmer.Msg


initWith : Flags -> ScanMailboxSettings -> ( Model, Cmd Msg )
initWith flags s =
    let
        ( im, _ ) =
            init flags

        imap =
            Util.Maybe.fromString s.imapConnection
                |> Maybe.map List.singleton
                |> Maybe.withDefault []

        ( nm, _, nc ) =
            update flags (ConnMsg (Comp.Dropdown.SetSelection imap)) im

        newSchedule =
            Data.CalEvent.fromEvent s.schedule
                |> Maybe.withDefault Data.CalEvent.everyMonth

        ( sm, sc ) =
            Comp.CalEventInput.init flags newSchedule
    in
    ( { nm
        | settings = s
        , enabled = s.enabled
        , deleteMail = s.deleteMail
        , receivedHours = s.receivedSinceHours
        , targetFolder = s.targetFolder
        , folders = s.folders
        , schedule = Data.Validated.Unknown newSchedule
        , direction = Maybe.andThen Data.Direction.fromString s.direction
        , scheduleModel = sm
        , formMsg = Nothing
        , yesNoDelete = Comp.YesNoDimmer.emptyModel
      }
    , Cmd.batch
        [ Api.getImapSettings flags "" ConnResp
        , nc
        , Cmd.map CalEventMsg sc
        ]
    )


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        initialSchedule =
            Data.Validated.Unknown Data.CalEvent.everyMonth

        ( sm, sc ) =
            Comp.CalEventInput.init flags Data.CalEvent.everyMonth
    in
    ( { settings = Api.Model.ScanMailboxSettings.empty
      , connectionModel =
            Comp.Dropdown.makeSingle
                { makeOption = \a -> { value = a, text = a }
                , placeholder = "Select connection..."
                }
      , enabled = False
      , deleteMail = False
      , receivedHours = Nothing
      , receivedHoursModel = Comp.IntField.init (Just 1) Nothing True "Received Since Hours"
      , foldersModel = Comp.StringListInput.init
      , folders = []
      , targetFolder = Nothing
      , direction = Nothing
      , schedule = initialSchedule
      , scheduleModel = sm
      , formMsg = Nothing
      , loading = 1
      , yesNoDelete = Comp.YesNoDimmer.emptyModel
      }
    , Cmd.batch
        [ Api.getImapSettings flags "" ConnResp
        , Cmd.map CalEventMsg sc
        ]
    )



--- Update


makeSettings : Model -> Validated ScanMailboxSettings
makeSettings model =
    let
        prev =
            model.settings

        conn =
            Comp.Dropdown.getSelected model.connectionModel
                |> List.head
                |> Maybe.map Valid
                |> Maybe.withDefault (Invalid [ "Connection missing" ] "")

        infolders =
            if model.folders == [] then
                Invalid [ "No folders given" ] []

            else
                Valid model.folders

        make smtp timer folders =
            { prev
                | imapConnection = smtp
                , enabled = model.enabled
                , receivedSinceHours = model.receivedHours
                , deleteMail = model.deleteMail
                , targetFolder = model.targetFolder
                , folders = folders
                , direction = Maybe.map Data.Direction.toString model.direction
                , schedule = Data.CalEvent.makeEvent timer
            }
    in
    Data.Validated.map3 make
        conn
        model.schedule
        infolders


withValidSettings : (ScanMailboxSettings -> Action) -> Model -> ( Model, Action, Cmd Msg )
withValidSettings mkAction model =
    case makeSettings model of
        Valid set ->
            ( { model | formMsg = Nothing }
            , mkAction set
            , Cmd.none
            )

        Invalid errs _ ->
            let
                errMsg =
                    String.join ", " errs
            in
            ( { model | formMsg = Just (BasicResult False errMsg) }
            , NoAction
            , Cmd.none
            )

        Unknown _ ->
            ( { model | formMsg = Just (BasicResult False "An unknown error occured") }
            , NoAction
            , Cmd.none
            )


update : Flags -> Msg -> Model -> ( Model, Action, Cmd Msg )
update flags msg model =
    case msg of
        CalEventMsg lmsg ->
            let
                ( cm, cc, cs ) =
                    Comp.CalEventInput.update flags
                        (Data.Validated.value model.schedule)
                        lmsg
                        model.scheduleModel
            in
            ( { model
                | schedule = cs
                , scheduleModel = cm
                , formMsg = Nothing
              }
            , NoAction
            , Cmd.map CalEventMsg cc
            )

        ConnMsg m ->
            let
                ( cm, cc ) =
                    Comp.Dropdown.update m model.connectionModel
            in
            ( { model
                | connectionModel = cm
                , formMsg = Nothing
              }
            , NoAction
            , Cmd.map ConnMsg cc
            )

        ConnResp (Ok list) ->
            let
                names =
                    List.map .name list.items

                cm =
                    Comp.Dropdown.makeSingleList
                        { makeOption = \a -> { value = a, text = a }
                        , placeholder = "Select Connection..."
                        , options = names
                        , selected = List.head names
                        }
            in
            ( { model
                | connectionModel = cm
                , loading = model.loading - 1
                , formMsg =
                    if names == [] then
                        Just
                            (BasicResult False
                                "No E-Mail connections configured. Goto E-Mail Settings to add one."
                            )

                    else
                        Nothing
              }
            , NoAction
            , Cmd.none
            )

        ConnResp (Err err) ->
            ( { model
                | formMsg = Just (BasicResult False (Util.Http.errorToString err))
                , loading = model.loading - 1
              }
            , NoAction
            , Cmd.none
            )

        ToggleEnabled ->
            ( { model
                | enabled = not model.enabled
                , formMsg = Nothing
              }
            , NoAction
            , Cmd.none
            )

        ToggleDeleteMail ->
            ( { model
                | deleteMail = not model.deleteMail
                , formMsg = Nothing
              }
            , NoAction
            , Cmd.none
            )

        ReceivedHoursMsg m ->
            let
                ( pm, val ) =
                    Comp.IntField.update m model.receivedHoursModel
            in
            ( { model
                | receivedHoursModel = pm
                , receivedHours = val
                , formMsg = Nothing
              }
            , NoAction
            , Cmd.none
            )

        SetTargetFolder str ->
            ( { model | targetFolder = Util.Maybe.fromString str }
            , NoAction
            , Cmd.none
            )

        FoldersMsg lm ->
            let
                ( fm, itemAction ) =
                    Comp.StringListInput.update lm model.foldersModel

                newList =
                    case itemAction of
                        Comp.StringListInput.AddAction s ->
                            Util.List.distinct (s :: model.folders)

                        Comp.StringListInput.RemoveAction s ->
                            List.filter (\e -> e /= s) model.folders

                        Comp.StringListInput.NoAction ->
                            model.folders
            in
            ( { model
                | foldersModel = fm
                , folders = newList
              }
            , NoAction
            , Cmd.none
            )

        DirectionMsg md ->
            ( { model | direction = md }
            , NoAction
            , Cmd.none
            )

        Submit ->
            withValidSettings
                SubmitAction
                model

        StartOnce ->
            withValidSettings
                StartOnceAction
                model

        Cancel ->
            ( model, CancelAction, Cmd.none )

        RequestDelete ->
            let
                ( ym, _ ) =
                    Comp.YesNoDimmer.update
                        Comp.YesNoDimmer.activate
                        model.yesNoDelete
            in
            ( { model | yesNoDelete = ym }
            , NoAction
            , Cmd.none
            )

        YesNoDeleteMsg lm ->
            let
                ( ym, flag ) =
                    Comp.YesNoDimmer.update lm model.yesNoDelete

                act =
                    if flag then
                        DeleteAction model.settings.id

                    else
                        NoAction
            in
            ( { model | yesNoDelete = ym }
            , act
            , Cmd.none
            )



--- View


isFormError : Model -> Bool
isFormError model =
    Maybe.map .success model.formMsg
        |> Maybe.map not
        |> Maybe.withDefault False


isFormSuccess : Model -> Bool
isFormSuccess model =
    Maybe.map .success model.formMsg
        |> Maybe.withDefault False


view : String -> Model -> Html Msg
view extraClasses model =
    div
        [ classList
            [ ( "ui form", True )
            , ( extraClasses, True )
            , ( "error", isFormError model )
            , ( "success", isFormSuccess model )
            ]
        ]
        [ Html.map YesNoDeleteMsg (Comp.YesNoDimmer.view model.yesNoDelete)
        , div
            [ classList
                [ ( "ui dimmer", True )
                , ( "active", model.loading > 0 )
                ]
            ]
            [ div [ class "ui text loader" ]
                [ text "Loading..."
                ]
            ]
        , div [ class "inline field" ]
            [ div [ class "ui checkbox" ]
                [ input
                    [ type_ "checkbox"
                    , onCheck (\_ -> ToggleEnabled)
                    , checked model.enabled
                    ]
                    []
                , label [] [ text "Enabled" ]
                ]
            , span [ class "small-info" ]
                [ text "Enable or disable this task."
                ]
            ]
        , div [ class "required field" ]
            [ label [] [ text "Mailbox" ]
            , Html.map ConnMsg (Comp.Dropdown.view model.connectionModel)
            , span [ class "small-info" ]
                [ text "The IMAP connection to use when sending notification mails."
                ]
            ]
        , div [ class "required field" ]
            [ label [] [ text "Folders" ]
            , Html.map FoldersMsg (Comp.StringListInput.view model.folders model.foldersModel)
            , span [ class "small-info" ]
                [ text "The folders to go through"
                ]
            ]
        , Html.map ReceivedHoursMsg
            (Comp.IntField.viewWithInfo
                "Select mails newer than `now - receivedHours`"
                model.receivedHours
                "field"
                model.receivedHoursModel
            )
        , div [ class "field" ]
            [ label [] [ text "Target folder" ]
            , input
                [ type_ "text"
                , onInput SetTargetFolder
                , Maybe.withDefault "" model.targetFolder |> value
                ]
                []
            , span [ class "small-info" ]
                [ text "Move all mails successfully submitted into this folder."
                ]
            ]
        , div [ class "inline field" ]
            [ div [ class "ui checkbox" ]
                [ input
                    [ type_ "checkbox"
                    , onCheck (\_ -> ToggleDeleteMail)
                    , checked model.deleteMail
                    ]
                    []
                , label [] [ text "Delete imported mails" ]
                ]
            , span [ class "small-info" ]
                [ text "Whether to delete all mails successfully imported into docspell. This only applies if "
                , em [] [ text "target folder" ]
                , text " is not set."
                ]
            ]
        , div [ class "required field" ]
            [ label [] [ text "Item direction" ]
            , div [ class "grouped fields" ]
                [ div [ class "field" ]
                    [ div [ class "ui radio checkbox" ]
                        [ input
                            [ type_ "radio"
                            , checked (model.direction == Nothing)
                            , onCheck (\_ -> DirectionMsg Nothing)
                            ]
                            []
                        , label [] [ text "Automatic" ]
                        ]
                    ]
                , div [ class "field" ]
                    [ div [ class "ui radio checkbox" ]
                        [ input
                            [ type_ "radio"
                            , checked (model.direction == Just Incoming)
                            , onCheck (\_ -> DirectionMsg (Just Incoming))
                            ]
                            []
                        , label [] [ text "Incoming" ]
                        ]
                    ]
                , div [ class "field" ]
                    [ div [ class "ui radio checkbox" ]
                        [ input
                            [ type_ "radio"
                            , checked (model.direction == Just Outgoing)
                            , onCheck (\_ -> DirectionMsg (Just Outgoing))
                            ]
                            []
                        , label [] [ text "Outgoing" ]
                        ]
                    ]
                , span [ class "small-info" ]
                    [ text "Sets the direction for an item. If you know all mails are incoming or "
                    , text "outgoing, you can set it here. Otherwise it will be guessed from looking "
                    , text "at sender and receiver."
                    ]
                ]
            ]
        , div [ class "required field" ]
            [ label []
                [ text "Schedule"
                , a
                    [ class "right-float"
                    , href "https://github.com/eikek/calev#what-are-calendar-events"
                    , target "_blank"
                    ]
                    [ i [ class "help icon" ] []
                    , text "Click here for help"
                    ]
                ]
            , Html.map CalEventMsg
                (Comp.CalEventInput.view ""
                    (Data.Validated.value model.schedule)
                    model.scheduleModel
                )
            , span [ class "small-info" ]
                [ text "Specify how often and when this task should run. "
                , text "Use English 3-letter weekdays. Either a single value, "
                , text "a list (ex. 1,2,3), a range (ex. 1..3) or a '*' (meaning all) "
                , text "is allowed for each part."
                ]
            ]
        , div [ class "ui divider" ] []
        , div
            [ classList
                [ ( "ui message", True )
                , ( "success", isFormSuccess model )
                , ( "error", isFormError model )
                , ( "hidden", model.formMsg == Nothing )
                ]
            ]
            [ Maybe.map .message model.formMsg
                |> Maybe.withDefault ""
                |> text
            ]
        , button
            [ class "ui primary button"
            , onClick Submit
            ]
            [ text "Submit"
            ]
        , button
            [ class "ui secondary button"
            , onClick Cancel
            ]
            [ text "Cancel"
            ]
        , button
            [ class "ui red button"
            , onClick RequestDelete
            ]
            [ text "Delete"
            ]
        , button
            [ class "ui right floated button"
            , onClick StartOnce
            ]
            [ text "Start Once"
            ]
        ]