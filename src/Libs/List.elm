module Libs.List exposing
    ( add
    , addAt
    , appendIf
    , appendOn
    , diff
    , dropRight
    , dropUntil
    , dropWhile
    , filterBy
    , filterNot
    , filterZip
    , find
    , findBy
    , findIndex
    , findIndexBy
    , get
    , groupBy
    , indexOf
    , indexedFilter
    , last
    , maximumBy
    , memberBy
    , memberWith
    , merge
    , mergeMaybe
    , minimumBy
    , move
    , moveBy
    , moveByRel
    , moveIndex
    , nonEmpty
    , nonEmptyMap
    , prepend
    , prependIf
    , prependOn
    , remove
    , removeAt
    , removeBy
    , replaceOrAppend
    , resultCollect
    , resultSeq
    , toggle
    , unique
    , uniqueBy
    , updateBy
    , zip
    , zipBy
    , zipWith
    , zipWithIndex
    )

import Dict exposing (Dict)
import Libs.Basics exposing (maxBy, minBy)
import Libs.Bool as B
import Libs.Maybe as Maybe
import Libs.Tuple3 as Tuple3
import Random
import Set


get : Int -> List a -> Maybe a
get index list =
    if index < 0 then
        Nothing

    else
        list |> List.drop index |> List.head


last : List a -> Maybe a
last list =
    case list of
        [] ->
            Nothing

        [ a ] ->
            Just a

        _ :: tail ->
            last tail


nonEmpty : List a -> Bool
nonEmpty list =
    not (List.isEmpty list)


nonEmptyMap : (List a -> b) -> b -> List a -> b
nonEmptyMap f default list =
    case list of
        [] ->
            default

        _ ->
            f list


find : (a -> Bool) -> List a -> Maybe a
find predicate list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            if predicate first then
                Just first

            else
                find predicate rest


findIndex : (a -> Bool) -> List a -> Maybe Int
findIndex =
    findIndexInner 0


findIndexInner : Int -> (a -> Bool) -> List a -> Maybe Int
findIndexInner index predicate list =
    case list of
        [] ->
            Nothing

        first :: rest ->
            if predicate first then
                Just index

            else
                findIndexInner (index + 1) predicate rest


findBy : (a -> b) -> b -> List a -> Maybe a
findBy matcher value list =
    find (\a -> matcher a == value) list


findIndexBy : (a -> b) -> b -> List a -> Maybe Int
findIndexBy matcher value list =
    findIndex (\a -> matcher a == value) list


filterBy : (a -> b) -> b -> List a -> List a
filterBy matcher value list =
    List.filter (\a -> matcher a == value) list


filterNot : (a -> Bool) -> List a -> List a
filterNot predicate list =
    list |> List.filter (\a -> not (predicate a))


indexedFilter : (Int -> a -> Bool) -> List a -> List a
indexedFilter p xs =
    xs |> List.indexedMap (\i a -> B.cond (p i a) (Just a) Nothing) |> List.filterMap identity


memberBy : (a -> b) -> b -> List a -> Bool
memberBy matcher value list =
    findBy matcher value list |> Maybe.isJust


memberWith : (a -> Bool) -> List a -> Bool
memberWith matcher list =
    find matcher list |> Maybe.isJust


indexOf : a -> List a -> Maybe Int
indexOf item xs =
    xs |> List.indexedMap (\i a -> ( i, a )) |> find (\( _, a ) -> a == item) |> Maybe.map Tuple.first


updateBy : (a -> b) -> b -> (a -> a) -> List a -> List a
updateBy matcher value transform list =
    list
        |> List.map
            (\a ->
                if matcher a == value then
                    transform a

                else
                    a
            )


zip : List b -> List a -> List ( a, b )
zip lb la =
    List.map2 (\a b -> ( a, b )) la lb


filterZip : (a -> Maybe b) -> List a -> List ( a, b )
filterZip f xs =
    List.filterMap (\a -> f a |> Maybe.map (\b -> ( a, b ))) xs


moveIndex : Int -> Int -> List a -> List a
moveIndex from to list =
    list |> get from |> Maybe.mapOrElse (\v -> list |> removeAt from |> addAt v to) list


move : a -> Int -> List a -> List a
move value position list =
    list |> findIndex (\a -> a == value) |> Maybe.mapOrElse (\index -> list |> moveIndex index position) list


moveBy : (a -> b) -> b -> Int -> List a -> List a
moveBy matcher value position list =
    list |> findIndexBy matcher value |> Maybe.mapOrElse (\index -> list |> moveIndex index position) list


moveByRel : (a -> b) -> b -> Int -> List a -> List a
moveByRel matcher value delta list =
    list |> findIndexBy matcher value |> Maybe.mapOrElse (\index -> list |> moveIndex index (index + delta)) list


removeAt : Int -> List a -> List a
removeAt index list =
    list |> List.indexedMap (\i a -> ( i, a )) |> List.filter (\( i, _ ) -> not (i == index)) |> List.map (\( _, a ) -> a)


remove : comparable -> List comparable -> List comparable
remove item list =
    list |> List.filter (\i -> i /= item)


removeBy : (a -> comparable) -> comparable -> List a -> List a
removeBy getKey item list =
    list |> List.filter (\i -> getKey i /= item)


add : a -> List a -> List a
add item list =
    list ++ [ item ]


addAt : a -> Int -> List a -> List a
addAt item index list =
    if index >= List.length list then
        list ++ [ item ]

    else if index < 0 then
        item :: list

    else
        -- list |> List.indexedMap (\i a -> ( i, a )) |> List.concatMap (\( i, a ) -> B.cond (i == index) [ item, a ] [ a ])
        -- list |> List.foldl (\a ( res, i ) -> ( List.concat [ res, B.cond (i == index) [ item, a ] [ a ] ], i + 1 )) ( [], 0 ) |> Tuple.first
        list |> List.foldr (\a ( res, i ) -> ( B.cond (i == index) (item :: a :: res) (a :: res), i - 1 )) ( [], List.length list - 1 ) |> Tuple.first


prepend : List a -> List a -> List a
prepend xs ys =
    List.append ys xs


prependIf : Bool -> a -> List a -> List a
prependIf predicate item list =
    if predicate then
        item :: list

    else
        list


prependOn : Maybe b -> (b -> a) -> List a -> List a
prependOn maybe transform list =
    case maybe of
        Just b ->
            transform b :: list

        Nothing ->
            list


appendIf : Bool -> a -> List a -> List a
appendIf predicate item list =
    if predicate then
        list ++ [ item ]

    else
        list


appendOn : Maybe b -> (b -> a) -> List a -> List a
appendOn maybe transform list =
    case maybe of
        Just b ->
            list ++ [ transform b ]

        Nothing ->
            list


replaceOrAppend : (a -> comparable) -> a -> List a -> List a
replaceOrAppend id item list =
    case
        list
            |> List.foldr
                (\a ( acc, it ) ->
                    case it of
                        Just i ->
                            if id a == id i then
                                ( i :: acc, Nothing )

                            else
                                ( a :: acc, it )

                        Nothing ->
                            ( a :: acc, it )
                )
                ( [], Just item )
    of
        ( acc, Just a ) ->
            acc ++ [ a ]

        ( acc, Nothing ) ->
            acc


zipWith : (a -> b) -> List a -> List ( a, b )
zipWith transform list =
    list |> List.map (\a -> ( a, transform a ))


zipWithIndex : List a -> List ( a, Int )
zipWithIndex list =
    list |> List.indexedMap (\i a -> ( a, i ))


zipBy : (a -> comparable) -> List a -> List a -> ( List a, List ( a, a ), List a )
zipBy getKey list1 list2 =
    let
        dict1 : Dict comparable a
        dict1 =
            list1 |> List.map (\a -> ( getKey a, a )) |> Dict.fromList

        dict2 : Dict comparable a
        dict2 =
            list2 |> List.map (\a -> ( getKey a, a )) |> Dict.fromList

        ( only1, both ) =
            list1 |> List.foldr (\a1 ( r1, r ) -> dict2 |> Dict.get (getKey a1) |> Maybe.map (\a2 -> ( r1, ( a1, a2 ) :: r )) |> Maybe.withDefault ( a1 :: r1, r )) ( [], [] )

        only2 : List a
        only2 =
            list2 |> List.filter (\a2 -> dict1 |> Dict.member (getKey a2) |> not)
    in
    ( only1, both, only2 )


diff : (a -> comparable) -> List a -> List a -> ( List a, List ( a, a ), List a )
diff getKey list1 list2 =
    zipBy getKey list1 list2 |> Tuple3.mapSecond (List.filter (\( a1, a2 ) -> a1 /= a2))


dropWhile : (a -> Bool) -> List a -> List a
dropWhile predicate list =
    case list of
        [] ->
            []

        x :: xs ->
            if predicate x then
                dropWhile predicate xs

            else
                list


dropUntil : (a -> Bool) -> List a -> List a
dropUntil predicate list =
    dropWhile (\a -> not (predicate a)) list


dropRight : Int -> List a -> List a
dropRight n list =
    list |> List.take (List.length list - n)


unique : List comparable -> List comparable
unique list =
    uniqueBy identity list


uniqueBy : (a -> comparable) -> List a -> List a
uniqueBy matcher list =
    list
        |> zipWith matcher
        |> List.foldl
            (\( item, key ) ( res, set ) ->
                if set |> Set.member key then
                    ( res, set )

                else
                    ( item :: res, set |> Set.insert key )
            )
            ( [], Set.empty )
        |> Tuple.first
        |> List.reverse


groupBy : (a -> comparable) -> List a -> Dict comparable (List a)
groupBy key list =
    List.foldr (\a dict -> dict |> Dict.update (key a) (\v -> v |> Maybe.mapOrElse (\x -> a :: x) [ a ] |> Just)) Dict.empty list


merge : (a -> comparable) -> (a -> a -> a) -> List a -> List a -> List a
merge getKey mergeValue l1 l2 =
    (l1 |> List.map (\a1 -> l2 |> find (\a2 -> getKey a1 == getKey a2) |> Maybe.mapOrElse (mergeValue a1) a1))
        ++ (l2 |> filterNot (\a2 -> l1 |> List.any (\a1 -> getKey a1 == getKey a2)))


mergeMaybe : (a -> Maybe comparable) -> (a -> a -> a) -> List a -> List a -> List a
mergeMaybe getKey mergeValue l1 l2 =
    (l1 |> List.map (\a1 -> l2 |> find (\a2 -> getKey a1 /= Nothing && getKey a1 == getKey a2) |> Maybe.mapOrElse (mergeValue a1) a1))
        ++ (l2 |> filterNot (\a2 -> l1 |> List.any (\a1 -> getKey a1 /= Nothing && getKey a1 == getKey a2)))


maximumBy : (a -> comparable) -> List a -> Maybe a
maximumBy getKey list =
    case list of
        x :: xs ->
            Just (List.foldl (maxBy getKey) x xs)

        _ ->
            Nothing


minimumBy : (a -> comparable) -> List a -> Maybe a
minimumBy getKey list =
    case list of
        x :: xs ->
            Just (List.foldl (minBy getKey) x xs)

        _ ->
            Nothing


toggle : comparable -> List comparable -> List comparable
toggle item list =
    if list |> List.member item then
        list |> List.filter (\i -> i /= item)

    else
        list ++ [ item ]


resultCollect : List (Result e a) -> ( List e, List a )
resultCollect list =
    List.foldr
        (\r ( errs, res ) ->
            case r of
                Ok a ->
                    ( errs, a :: res )

                Err e ->
                    ( e :: errs, res )
        )
        ( [], [] )
        list


resultSeq : List (Result e a) -> Result (List e) (List a)
resultSeq list =
    case resultCollect list of
        ( [], res ) ->
            Ok res

        ( errs, _ ) ->
            Err errs


genSeq : List (Random.Generator a) -> Random.Generator (List a)
genSeq generators =
    generators |> List.foldr (Random.map2 (::)) (Random.constant [])
