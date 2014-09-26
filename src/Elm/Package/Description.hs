{-# LANGUAGE OverloadedStrings #-}
module Elm.Package.Description where

import Control.Applicative
import Control.Arrow (first)
import Control.Monad.Error
import qualified Control.Exception as E
import Data.Aeson
import Data.Aeson.Types (Parser)
import Data.Aeson.Encode.Pretty
import Data.Maybe (fromMaybe)
import qualified Data.List as List
import qualified Data.ByteString.Lazy as BS
import qualified Data.HashMap.Strict as Map
import qualified Data.Text as T

import qualified Elm.Package.Name as N
import qualified Elm.Package.Version as V
import qualified Elm.Package.Constraint as C
import qualified Elm.Package.Paths as Path


data Description = Description
    { name :: N.Name
    , version :: V.Version
    , summary :: String
    , description :: String
    , license :: String
    , repo :: String
    , exposed :: [String]
    , native :: [String]
    , elmVersion :: V.Version
    , sourceDirs :: [FilePath]
    , dependencies :: [(N.Name, C.Constraint)]
    }


defaultDescription :: Description
defaultDescription =
    Description
    { name = N.Name "USER" "PROJECT"
    , version = V.Version 0 0 0
    , summary = "helpful summary of your project, less than 80 characters"
    , description = "full description of this project, describe your use case"
    , license = "BSD3"
    , repo = "https://github.com/USER/PROJECT.git"
    , exposed = []
    , native = []
    , elmVersion = error "TODO: fix this"
    , sourceDirs = []
    , dependencies = []
    }


instance ToJSON Description where
  toJSON d =
      object $
      [ "version"         .= version d
      , "summary"         .= summary d
      , "description"     .= description d
      , "license"         .= license d
      , "repository"      .= repo d
      , "exposed-modules" .= exposed d
      , "elm-version"     .= elmVersion d
      , "dependencies"    .= (jsonDeps . dependencies $ d)
      ] ++ sourceDirectories ++ nativeModules
    where
      jsonDeps deps =
          Map.fromList $ map (first (T.pack . N.toString)) deps

      nativeModules
          | null (native d) = []
          | otherwise       = [ "native-modules" .= native d ]

      sourceDirectories
          | null (sourceDirs d) = []
          | otherwise = [ "source-directories" .= sourceDirs d ]


instance FromJSON Description where
    parseJSON (Object obj) =
        do version <- get obj "version" "your projects version number"

           summary <- get obj "summary" "a short summary of your project"
           when (length summary >= 80) $
               fail "'summary' must be less than 80 characters"

           desc <- get obj "description" "an extended description of your project \
                                         \and how to get started with it."
           license <- get obj "license" "license information (BSD3 is recommended)"

           repo <- get obj "repository" "a link to the project's GitHub repo"
           name <- case repoToName repo of
                     Left err -> fail err
                     Right nm -> return nm

           exposed <- get obj "exposed-modules" "a list of modules exposed to users"
           
           native <- fromMaybe [] <$> (obj .:? "native-modules")

           elmVersion <- get obj "elm-version" "the version of the Elm compiler you are using"

           sourceDirs <- fromMaybe [] <$> (obj .:? "source-directories")

           deps <- getDependencies obj

           return $ Description name version summary desc license repo exposed native elmVersion sourceDirs deps

    parseJSON _ = mzero

getDependencies :: Object -> Parser [(N.Name, C.Constraint)]
getDependencies obj = 
    toDeps =<< get obj "dependencies" "a listing of your project's dependencies"
    where
      toDeps deps =
          forM (Map.toList deps) $ \(f,c) ->
              case (N.fromString f, C.fromString c) of
                (Just name, Just constr) -> return (name, constr)
                (Nothing, _) -> fail $ N.errorMsg f
                (_, Nothing) -> fail $ "Invalid constraint: " ++ c

get :: FromJSON a => Object -> T.Text -> String -> Parser a
get obj field desc =
    do maybe <- obj .:? field
       case maybe of
         Just value -> return value
         Nothing -> fail $ "Missing field " ++ show field ++ ", " ++ desc ++ ".\n" ++
                           "    Check out an example " ++ Path.description ++ " file here:" ++
                           "    <https://github.com/evancz/automaton/blob/master/elm_dependencies.json>"

repoToName :: String -> Either String N.Name
repoToName repo =
    if not (end `List.isSuffixOf` repo)
        then Left msg
        else
            do  path <- getPath
                let raw = take (length path - length end) path
                case N.fromString raw of
                  Nothing   -> Left msg
                  Just name -> Right name
    where
      getPath
          | http  `List.isPrefixOf` repo = Right $ drop (length http ) repo
          | https `List.isPrefixOf` repo = Right $ drop (length https) repo
          | otherwise = Left msg

      http  = "http://github.com/"
      https = "https://github.com/"
      end = ".git"
      msg =
          "the 'repository' field must point to a GitHub project for now, something\n\
          \like <https://github.com/USER/PROJECT.git> where USER is your GitHub name\n\
          \and PROJECT is the repo you want to upload."

withDescription :: FilePath -> (Description -> ErrorT String IO a) -> ErrorT String IO a
withDescription path handle =
    do json <- readPath
       case eitherDecode json of
         Left err -> throwError $ "Error reading file " ++ path ++ ":\n    " ++ err
         Right ds -> handle ds
    where
      readPath :: ErrorT String IO BS.ByteString
      readPath = do
        result <- liftIO $ E.catch (Right <$> BS.readFile path)
                                   (\err -> return $ Left (err :: IOError))
        case result of
          Right bytes -> return bytes
          Left _ -> throwError $
                    "could not find " ++ path ++ " file. You may need to create one.\n" ++
                    "    For an example of how to fill in the dependencies file, check out\n" ++
                    "    <https://github.com/evancz/automaton/blob/master/elm_dependencies.json>"

withNative :: FilePath -> ([String] -> ErrorT String IO a) -> ErrorT String IO a
withNative path handle =
    withDescription path (handle . native)

descriptionAt :: FilePath -> ErrorT String IO Description
descriptionAt filePath =
    withDescription filePath return

-- | Encode dependencies in a canonical JSON format
prettyJSON :: Description -> BS.ByteString
prettyJSON =
    encodePretty' config
  where
    config = defConfig { confCompare = order }
    order =
        keyOrder
        [ "name"
        , "version"
        , "summary"
        , "description"
        , "license"
        , "repo"
        , "exposed-modules"
        , "native-modules"
        , "elm-version"
        , "source-directories"
        , "dependencies"
        ]
