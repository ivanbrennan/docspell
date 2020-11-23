module Page.Upload.Data exposing
    ( Model
    , Msg(..)
    , emptyModel
    , hasErrors
    , isCompleted
    , isDone
    , isError
    , isIdle
    , isLoading
    , isSuccessAll
    , mkLanguageItem
    , uploadAllTracker
    )

import Api.Model.BasicResult exposing (BasicResult)
import Comp.Dropzone
import Comp.FixedDropdown
import Data.Language exposing (Language)
import Dict exposing (Dict)
import File exposing (File)
import Http
import Set exposing (Set)
import Util.File exposing (makeFileId)


type alias Model =
    { incoming : Bool
    , singleItem : Bool
    , files : List File
    , completed : Set String
    , errored : Set String
    , loading : Dict String Int
    , dropzone : Comp.Dropzone.Model
    , skipDuplicates : Bool
    , languageModel : Comp.FixedDropdown.Model Language
    , language : Maybe Language
    }


dropzoneSettings : Comp.Dropzone.Settings
dropzoneSettings =
    let
        ds =
            Comp.Dropzone.defaultSettings
    in
    { ds
        | classList =
            \m ->
                [ ( "ui attached blue placeholder segment dropzone", True )
                , ( "dragging", m.hover )
                , ( "disabled", not m.active )
                ]
    }


mkLanguageItem : Language -> Comp.FixedDropdown.Item Language
mkLanguageItem lang =
    Comp.FixedDropdown.Item lang (Data.Language.toName lang)


emptyModel : Model
emptyModel =
    { incoming = True
    , singleItem = False
    , files = []
    , completed = Set.empty
    , errored = Set.empty
    , loading = Dict.empty
    , dropzone = Comp.Dropzone.init dropzoneSettings
    , skipDuplicates = True
    , languageModel =
        Comp.FixedDropdown.init
            (List.map mkLanguageItem Data.Language.all)
    , language = Nothing
    }


type Msg
    = SubmitUpload
    | SingleUploadResp String (Result Http.Error BasicResult)
    | GotProgress String Http.Progress
    | ToggleIncoming
    | ToggleSingleItem
    | Clear
    | DropzoneMsg Comp.Dropzone.Msg
    | ToggleSkipDuplicates
    | LanguageMsg (Comp.FixedDropdown.Msg Language)


isLoading : Model -> File -> Bool
isLoading model file =
    Dict.member (makeFileId file) model.loading


isCompleted : Model -> File -> Bool
isCompleted model file =
    Set.member (makeFileId file) model.completed


isError : Model -> File -> Bool
isError model file =
    Set.member (makeFileId file) model.errored


isIdle : Model -> File -> Bool
isIdle model file =
    not (isLoading model file || isCompleted model file || isError model file)


uploadAllTracker : String
uploadAllTracker =
    "upload-all"


isDone : Model -> Bool
isDone model =
    List.map makeFileId model.files
        |> List.all (\id -> Set.member id model.completed || Set.member id model.errored)


isSuccessAll : Model -> Bool
isSuccessAll model =
    List.map makeFileId model.files
        |> List.all (\id -> Set.member id model.completed)


hasErrors : Model -> Bool
hasErrors model =
    not (Set.isEmpty model.errored)
