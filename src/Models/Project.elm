module Models.Project exposing (Project, compute, computeRelations, computeTables, computeTypes, create, decode, downloadContent, downloadFilename, duplicate, encode, new)

import Conf
import Dict exposing (Dict)
import Json.Decode as Decode
import Json.Encode as Encode exposing (Value)
import Libs.Dict as Dict
import Libs.Json.Decode as Decode
import Libs.Json.Encode as Encode
import Libs.List as List
import Libs.String as String
import Libs.Time as Time
import Models.Project.CustomType as CustomType exposing (CustomType)
import Models.Project.CustomTypeId exposing (CustomTypeId)
import Models.Project.Layout as Layout exposing (Layout)
import Models.Project.LayoutName as LayoutName exposing (LayoutName)
import Models.Project.ProjectId as ProjectId exposing (ProjectId)
import Models.Project.ProjectName as ProjectName exposing (ProjectName)
import Models.Project.ProjectSettings as ProjectSettings exposing (ProjectSettings)
import Models.Project.ProjectStorage as ProjectStorage exposing (ProjectStorage)
import Models.Project.Relation as Relation exposing (Relation)
import Models.Project.SchemaName exposing (SchemaName)
import Models.Project.Source as Source exposing (Source)
import Models.Project.Table as Table exposing (Table)
import Models.Project.TableId exposing (TableId)
import PagesComponents.Projects.Id_.Models.Notes exposing (Notes, NotesKey)
import Time


type alias Project =
    { id : ProjectId
    , name : ProjectName
    , sources : List Source
    , tables : Dict TableId Table -- computed from sources, do not update directly (see compute function)
    , relations : List Relation -- computed from sources, do not update directly (see compute function)
    , types : Dict CustomTypeId CustomType -- computed from sources, do not update directly (see compute function)
    , notes : Dict NotesKey Notes
    , usedLayout : LayoutName
    , layouts : Dict LayoutName Layout
    , settings : ProjectSettings
    , storage : ProjectStorage
    , createdAt : Time.Posix
    , updatedAt : Time.Posix
    }


new : ProjectId -> ProjectName -> List Source -> Dict NotesKey Notes -> LayoutName -> Dict LayoutName Layout -> ProjectSettings -> ProjectStorage -> Time.Posix -> Time.Posix -> Project
new id name sources notes usedLayout layouts settings storage createdAt updatedAt =
    { id = id
    , name = name
    , sources = sources
    , tables = Dict.empty
    , relations = []
    , types = Dict.empty
    , notes = notes
    , usedLayout = usedLayout
    , layouts = layouts
    , settings = settings
    , storage = storage
    , createdAt = createdAt
    , updatedAt = updatedAt
    }
        |> compute


create : ProjectId -> ProjectName -> Source -> Project
create id name source =
    new id
        name
        [ source ]
        Dict.empty
        Conf.constants.defaultLayout
        (Dict.fromList [ ( Conf.constants.defaultLayout, Layout.empty source.createdAt ) ])
        (ProjectSettings.init (mostUsedSchema source.tables))
        ProjectStorage.Browser
        source.createdAt
        source.updatedAt


duplicate : List ProjectName -> ProjectId -> Project -> Project
duplicate takenNames projectId project =
    { project | id = projectId, name = String.unique takenNames project.name }


mostUsedSchema : Dict TableId Table -> SchemaName
mostUsedSchema table =
    table
        |> Dict.keys
        |> List.map Tuple.first
        |> List.groupBy identity
        |> Dict.map (\_ -> List.length)
        |> Dict.toList
        |> List.maximumBy (\( _, count ) -> count)
        |> Maybe.map Tuple.first
        |> Maybe.withDefault Conf.schema.empty


compute : Project -> Project
compute project =
    (project.sources |> computeTables project.settings)
        |> (\tables ->
                { project
                    | tables = tables
                    , relations = project.sources |> computeRelations tables
                    , types = project.sources |> computeTypes
                }
           )


computeTables : ProjectSettings -> List Source -> Dict TableId Table
computeTables settings sources =
    sources
        |> List.filter .enabled
        |> List.map (\s -> s.tables |> Dict.filter (\_ -> shouldDisplayTable settings))
        |> List.foldr (Dict.fuse Table.merge) Dict.empty


shouldDisplayTable : ProjectSettings -> Table -> Bool
shouldDisplayTable settings table =
    let
        isSchemaRemoved : Bool
        isSchemaRemoved =
            settings.removedSchemas |> List.member table.schema

        isViewRemoved : Bool
        isViewRemoved =
            table.view && settings.removeViews

        isTableRemoved : Bool
        isTableRemoved =
            table.id |> ProjectSettings.removeTable settings.removedTables
    in
    not isSchemaRemoved && not isViewRemoved && not isTableRemoved


computeRelations : Dict TableId Table -> List Source -> List Relation
computeRelations tables sources =
    sources
        |> List.filter .enabled
        |> List.map (\s -> s.relations |> List.filter (shouldDisplayRelation tables))
        |> List.foldr (List.merge .id Relation.merge) []


shouldDisplayRelation : Dict TableId Table -> Relation -> Bool
shouldDisplayRelation tables relation =
    (tables |> Dict.member relation.src.table) && (tables |> Dict.member relation.ref.table)


computeTypes : List Source -> Dict CustomTypeId CustomType
computeTypes sources =
    sources
        |> List.filter .enabled
        |> List.map .types
        |> List.foldr (Dict.fuse CustomType.merge) Dict.empty


currentVersion : Int
currentVersion =
    -- compatibility version for Project JSON, when you have breaking change, increment it and handle needed migrations
    2


downloadFilename : Project -> String
downloadFilename project =
    (project.name |> String.replace ".sql" "") ++ ".azimutt.json"


downloadContent : Project -> String
downloadContent project =
    (project |> encode |> Encode.encode 2) ++ "\n"


encode : Project -> Value
encode value =
    Encode.notNullObject
        [ ( "id", value.id |> ProjectId.encode )
        , ( "name", value.name |> ProjectName.encode )
        , ( "sources", value.sources |> Encode.list Source.encode )
        , ( "notes", value.notes |> Encode.withDefault (Encode.dict identity Encode.string) Dict.empty )
        , ( "usedLayout", value.usedLayout |> LayoutName.encode )
        , ( "layouts", value.layouts |> Encode.dict LayoutName.toString Layout.encode )
        , ( "settings", value.settings |> Encode.withDefaultDeep ProjectSettings.encode (ProjectSettings.init Conf.schema.empty) )
        , ( "storage", value.storage |> Encode.withDefault ProjectStorage.encode ProjectStorage.Browser )
        , ( "createdAt", value.createdAt |> Time.encode )
        , ( "updatedAt", value.updatedAt |> Time.encode )
        , ( "version", currentVersion |> Encode.int )
        ]


decode : Decode.Decoder Project
decode =
    Decode.map11 decodeProject
        (Decode.field "id" ProjectId.decode)
        (Decode.field "name" ProjectName.decode)
        (Decode.field "sources" (Decode.list Source.decode))
        (Decode.defaultField "notes" (Decode.dict Decode.string) Dict.empty)
        (Decode.defaultField "layout" Layout.decode (Layout.empty Time.zero))
        (Decode.defaultField "usedLayout" LayoutName.decode Conf.constants.defaultLayout)
        (Decode.defaultField "layouts" (Decode.customDict LayoutName.fromString Layout.decode) Dict.empty)
        (Decode.defaultFieldDeep "settings" ProjectSettings.decode (ProjectSettings.init Conf.schema.empty))
        (Decode.defaultField "storage" ProjectStorage.decode ProjectStorage.Browser)
        (Decode.defaultField "createdAt" Time.decode Time.zero)
        (Decode.defaultField "updatedAt" Time.decode Time.zero)


decodeProject : ProjectId -> ProjectName -> List Source -> Dict NotesKey Notes -> Layout -> LayoutName -> Dict LayoutName Layout -> ProjectSettings -> ProjectStorage -> Time.Posix -> Time.Posix -> Project
decodeProject id name sources notes layout usedLayout layouts settings storage createdAt updatedAt =
    let
        allLayouts : Dict LayoutName Layout
        allLayouts =
            -- migrate from a default layout to only layouts
            if layout == Layout.empty Time.zero then
                layouts

            else
                layouts |> Dict.insert Conf.constants.defaultLayout layout
    in
    new id name sources notes usedLayout allLayouts settings storage createdAt updatedAt
