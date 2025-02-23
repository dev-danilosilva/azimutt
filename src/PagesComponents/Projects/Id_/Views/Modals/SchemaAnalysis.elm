module PagesComponents.Projects.Id_.Views.Modals.SchemaAnalysis exposing (viewSchemaAnalysis)

import Components.Atoms.Button as Button
import Components.Atoms.Icon as Icon exposing (Icon(..))
import Components.Molecules.Modal as Modal
import Components.Molecules.Tooltip as Tooltip
import Conf
import Dict exposing (Dict)
import Html exposing (Html, div, h3, h4, h5, p, span, text)
import Html.Attributes exposing (class, classList, id)
import Html.Events exposing (onClick)
import Libs.Bool as B
import Libs.Dict as Dict
import Libs.Html exposing (bText, extLink)
import Libs.Html.Attributes exposing (css)
import Libs.List as List
import Libs.Models.HtmlId exposing (HtmlId)
import Libs.Regex as Regex
import Libs.String as String
import Libs.Tailwind as Tw exposing (sm)
import Models.Project.ColumnName as ColumnName exposing (ColumnName)
import Models.Project.ColumnRef as ColumnRef exposing (ColumnRef)
import Models.Project.ColumnType exposing (ColumnType)
import Models.Project.SchemaName exposing (SchemaName)
import Models.Project.TableId as TableId exposing (TableId)
import Models.Project.TableName exposing (TableName)
import PagesComponents.Projects.Id_.Models exposing (Msg(..), SchemaAnalysisDialog, SchemaAnalysisMsg(..))
import PagesComponents.Projects.Id_.Models.ErdTable exposing (ErdTable)



{-
   Improve analysis:
    - better missing relations (singular table name present in column name, and follower by an existing column name in this table)
    - identify missing polymorphic relations (two successive columns with the same name ending with _type and _id)
    - '_at' columns not of date type
    - % of nullable columns in a table (warn if > 50%)
    - ?identify PII

   https://schemaspy.org/sample/anomalies.html
   - Tables that contain a single column
   - Tables without indexes
   - Columns whose default value is the word 'NULL' or 'null'
   - Tables with incrementing column names, potentially indicating denormalization
-}


viewSchemaAnalysis : Bool -> SchemaName -> Dict TableId ErdTable -> SchemaAnalysisDialog -> Html Msg
viewSchemaAnalysis opened defaultSchema tables model =
    let
        titleId : HtmlId
        titleId =
            model.id ++ "-title"
    in
    Modal.modal { id = model.id, titleId = titleId, isOpen = opened, onBackgroundClick = ModalClose (SchemaAnalysisMsg SAClose) }
        [ viewHeader titleId
        , viewAnalysis model.opened defaultSchema tables
        , viewFooter
        ]


viewHeader : HtmlId -> Html msg
viewHeader titleId =
    div [ css [ "pt-6 px-6", sm [ "flex items-start" ] ] ]
        [ div [ css [ "mx-auto flex-shrink-0 flex items-center justify-center h-12 w-12 rounded-full bg-primary-100", sm [ "mx-0 h-10 w-10" ] ] ]
            [ Icon.outline Beaker "text-primary-600"
            ]
        , div [ css [ "mt-3 text-center", sm [ "mt-0 ml-4 text-left" ] ] ]
            [ h3 [ id titleId, class "text-lg leading-6 font-medium text-gray-900" ] [ text "Schema analysis" ]
            , p [ class "text-sm text-gray-500" ]
                [ text "Let's find out if we can find improvements for your schema..." ]
            ]
        ]


viewAnalysis : HtmlId -> SchemaName -> Dict TableId ErdTable -> Html Msg
viewAnalysis opened defaultSchema tables =
    div [ class "px-6" ]
        [ viewMissingPrimaryKey "missing-pks" opened defaultSchema (computeMissingPrimaryKey tables)
        , viewMissingRelations "missing-relations" opened defaultSchema (computeMissingRelations tables)
        , viewHeterogeneousTypes "heterogeneous-types" opened defaultSchema (computeHeterogeneousTypes tables)
        , viewBigTables "big-tables" opened defaultSchema (computeBigTables tables)
        ]


viewFooter : Html Msg
viewFooter =
    div [ class "px-6 py-3 mt-3 flex items-center justify-between flex-row-reverse bg-gray-50 rounded-b-lg" ]
        [ Button.primary3 Tw.primary [ class "ml-3", onClick (ModalClose (SchemaAnalysisMsg SAClose)) ] [ text "Close" ]
        , span [] [ text "If you've got any ideas for improvements, ", extLink "https://github.com/azimuttapp/azimutt/discussions/75" [ class "link" ] [ text "please let us know" ], text "." ]
        ]



-- MISSING PRIMARY KEY


computeMissingPrimaryKey : Dict TableId ErdTable -> List ErdTable
computeMissingPrimaryKey tables =
    tables |> Dict.values |> List.filter (\t -> t.primaryKey == Nothing)


viewMissingPrimaryKey : HtmlId -> HtmlId -> SchemaName -> List ErdTable -> Html Msg
viewMissingPrimaryKey htmlId opened defaultSchema missingPks =
    viewSection htmlId
        opened
        "All tables have a primary key"
        (missingPks |> List.length)
        (\nb -> "Found " ++ (nb |> String.pluralize "table") ++ " without a primary key")
        [ div []
            (missingPks
                |> List.map
                    (\t ->
                        div [ class "flex justify-between items-center my-1" ]
                            [ div [] [ bText (TableId.show defaultSchema t.id), text " has no primary key" ]
                            , Button.primary1 Tw.primary [ class "ml-3", onClick (ShowTable t.id Nothing) ] [ text "Show table" ]
                            ]
                    )
            )
        , p [ class "prose mb-3 text-sm text-gray-500" ]
            [ text "It's not always required to have a primary key but strongly encouraged in most case. Make sure this is what you want!" ]
        ]



-- MISSING RELATIONS


type alias ColumnInfo =
    { table : TableId, column : ColumnName, kind : ColumnType }


type alias MissingRelation =
    { src : ColumnInfo
    , ref : ColumnInfo
    }


type alias MissingRef =
    { src : ColumnInfo
    }


infoToRef : ColumnInfo -> ColumnRef
infoToRef info =
    { table = info.table, column = info.column }


computeMissingRelations : Dict TableId ErdTable -> ( List MissingRelation, List MissingRef )
computeMissingRelations tables =
    tables
        |> Dict.values
        |> List.concatMap
            (\t ->
                t.columns
                    |> Dict.values
                    |> List.filter (\c -> (c.name |> String.toLower |> Regex.matchI "_ids?$") && not c.isPrimaryKey && (c.inRelations |> List.isEmpty) && (c.outRelations |> List.isEmpty))
                    |> List.map (\c -> { table = t.id, column = c.name, kind = c.kind })
            )
        |> List.map (\src -> ( src, tables |> getRef src ))
        |> List.partition (\( _, maybeRef ) -> maybeRef /= Nothing)
        |> Tuple.mapFirst (List.filterMap (\( src, maybeRef ) -> maybeRef |> Maybe.map (\ref -> { src = src, ref = ref })))
        |> Tuple.mapSecond (List.map (\( src, _ ) -> { src = src }))


getRef : ColumnInfo -> Dict TableId ErdTable -> Maybe ColumnInfo
getRef src tables =
    let
        words : List String
        words =
            src.column |> String.toLower |> String.split "_" |> List.dropRight 1

        prefix : TableName
        prefix =
            words |> String.join "_"

        tableNames : List TableName
        tableNames =
            [ words |> String.join "_" |> String.plural, words |> List.drop 1 |> String.join "_" |> String.plural ]
    in
    tables
        |> Dict.filter (\( schema, table ) _ -> (schema == Tuple.first src.table) && (table /= Tuple.second src.table) && (tableNames |> List.member (String.toLower table)))
        |> Dict.values
        |> List.sortBy (\t -> 0 - String.length t.name)
        |> List.head
        |> Maybe.andThen
            (\t ->
                t.columns
                    |> Dict.find (\name _ -> String.toLower name == "id" || String.toLower name == (prefix ++ "_id"))
                    |> Maybe.map (\( _, c ) -> { table = t.id, column = c.name, kind = c.kind })
            )


kindMatch : MissingRelation -> Bool
kindMatch rel =
    if (rel.src.column |> String.toLower |> String.endsWith "_ids") && (rel.src.kind |> String.endsWith "[]") then
        (rel.src.kind |> String.dropRight 2) == rel.ref.kind

    else
        rel.src.kind == rel.ref.kind


viewMissingRelations : HtmlId -> HtmlId -> SchemaName -> ( List MissingRelation, List MissingRef ) -> Html Msg
viewMissingRelations htmlId opened defaultSchema ( missingRels, missingRefs ) =
    viewSection htmlId
        opened
        "No potentially missing relation found"
        ((missingRels |> List.length) + (missingRefs |> List.length))
        (\nb -> "Found " ++ (nb |> String.pluralize "potentially missing relation"))
        [ div []
            (missingRels
                |> List.sortBy (\rel -> ColumnRef.show defaultSchema rel.ref ++ " ← " ++ ColumnRef.show defaultSchema rel.src)
                |> List.map
                    (\rel ->
                        div [ class "flex justify-between items-center py-1" ]
                            [ div []
                                [ text (TableId.show defaultSchema rel.ref.table)
                                , span [ class "text-gray-500" ] [ text (ColumnName.withName rel.ref.column "") ]
                                , Icon.solid ArrowNarrowLeft "inline mx-1"
                                , text (TableId.show defaultSchema rel.src.table)
                                , span [ class "text-gray-500" ] [ text (ColumnName.withName rel.src.column "") ]
                                ]
                            , div [ class "ml-3" ]
                                [ B.cond (kindMatch rel) (span [] []) (span [ class "text-gray-400 mr-3" ] [ Icon.solid Exclamation "inline", text (" " ++ rel.ref.kind ++ " vs " ++ rel.src.kind) ])
                                , Button.primary1 Tw.primary [ onClick (CreateRelation (infoToRef rel.src) (infoToRef rel.ref)) ] [ text "Add relation" ]
                                ]
                            ]
                    )
            )
        , if missingRefs |> List.isEmpty then
            div [] []

          else
            div []
                [ h5 [ class "mt-1 font-medium" ] [ text "Some columns may need a relation, but can't find a related table:" ]
                , div []
                    (missingRefs
                        |> List.map
                            (\rel ->
                                div [ class "ml-3" ]
                                    [ text (TableId.show defaultSchema rel.src.table)
                                    , span [ class "text-gray-500" ] [ text (ColumnName.withName rel.src.column "") ]
                                    , span [ class "text-gray-400" ] [ text (" (" ++ rel.src.kind ++ ")") ]
                                    ]
                            )
                    )
                ]
        ]



-- HETEROGENEOUS TYPES


computeHeterogeneousTypes : Dict TableId ErdTable -> List ( ColumnName, List ( ColumnType, List TableId ) )
computeHeterogeneousTypes tables =
    tables
        |> Dict.values
        |> List.concatMap (\t -> t.columns |> Dict.values |> List.filter (\c -> c.kind /= Conf.schema.column.unknownType) |> List.map (\c -> { table = t.id, column = c.name, kind = c.kind }))
        |> List.groupBy .column
        |> Dict.toList
        |> List.map (\( col, cols ) -> ( col, cols |> List.groupBy .kind |> Dict.map (\_ -> List.map .table) |> Dict.toList ))
        |> List.filter (\( _, cols ) -> (cols |> List.length) > 1)


viewHeterogeneousTypes : HtmlId -> HtmlId -> SchemaName -> List ( ColumnName, List ( ColumnType, List TableId ) ) -> Html Msg
viewHeterogeneousTypes htmlId opened defaultSchema heterogeneousTypes =
    viewSection htmlId
        opened
        "No heterogeneous types found"
        (heterogeneousTypes |> List.length)
        (\nb -> "Found " ++ (nb |> String.pluralize "column") ++ " with heterogeneous types")
        (p [ class "prose mb-3 text-sm text-gray-500" ]
            [ text
                ("There is nothing wrong intrinsically with heterogeneous types "
                    ++ "but sometimes, the same concept stored in different format may not be ideal and having everything aligned is clearer. "
                    ++ "But of course, not every column with the same name is the same thing, so just look at the to know, not to fix everything."
                )
            ]
            :: (heterogeneousTypes
                    |> List.map
                        (\( col, types ) ->
                            div []
                                [ bText col
                                , text " has types: "
                                , span [ class "text-gray-500" ]
                                    (types
                                        |> List.map (\( t, ids ) -> text t |> Tooltip.t (ids |> List.map (TableId.show defaultSchema) |> String.join ", "))
                                        |> List.intersperse (text ", ")
                                    )
                                ]
                        )
               )
        )



-- BIG TABLES


computeBigTables : Dict TableId ErdTable -> List ErdTable
computeBigTables tables =
    tables
        |> Dict.values
        |> List.filter (\t -> (t.columns |> Dict.size) > 30)
        |> List.sortBy (\t -> t.columns |> Dict.size |> negate)


viewBigTables : HtmlId -> HtmlId -> SchemaName -> List ErdTable -> Html Msg
viewBigTables htmlId opened defaultSchema bigTables =
    viewSection htmlId
        opened
        "No big table found"
        (bigTables |> List.length)
        (\nb -> "Found " ++ (nb |> String.pluralize "table") ++ " too big")
        [ div [] (bigTables |> List.map (\t -> div [] [ text ((t.columns |> Dict.size |> String.pluralize "column") ++ ": "), bText (TableId.show defaultSchema t.id) ]))
        , div [ class "mt-1 text-gray-500" ]
            [ text "See "
            , extLink "/blog/why-you-should-avoid-tables-with-many-columns-and-how-to-fix-them"
                [ css [ "link" ] ]
                [ text "Why you should avoid tables with many columns, and how to fix them"
                ]
            ]
        ]



-- HELPERS


viewSection : HtmlId -> HtmlId -> String -> Int -> (Int -> String) -> List (Html Msg) -> Html Msg
viewSection htmlId opened successTitle errorCount failureTitle content =
    let
        isOpen : Bool
        isOpen =
            opened == htmlId
    in
    if errorCount == 0 then
        div [ class "mt-3" ]
            [ h4 [ class "leading-5 font-medium" ]
                [ Icon.solid Check "inline mr-3 text-green-500"
                , text successTitle
                ]
            ]

    else
        div [ class "mt-3" ]
            [ h4 [ class "mb-1 leading-5 font-medium cursor-pointer", onClick (SchemaAnalysisMsg (SASectionToggle htmlId)) ]
                [ Icon.solid LightBulb "inline mr-3 text-yellow-500"
                , text (errorCount |> failureTitle)
                , Icon.solid ChevronDown ("inline transform transition " ++ B.cond isOpen "-rotate-180" "")
                ]
            , div [ classList [ ( "hidden", not isOpen ) ] ] content
            ]
