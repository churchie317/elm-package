module Elm.Package.Name where

import Control.Applicative ((<$>), (<*>))
import Control.Monad.Error
import Data.Aeson
import Data.Binary
import qualified Data.Text as T
import qualified Data.Maybe as Maybe


data Name = Name
    { user :: String
    , project :: String
    }


toString :: Name -> String
toString name =
    user name ++ "/" ++ project name


toFilePath :: Name -> FilePath
toFilePath name =
    user name ++ "-" ++ project name


fromString :: String -> Maybe Name
fromString string =
    case break (=='/') string of
      ( user@(_:_), '/' : project@(_:_) )
          | all (/='/') project -> Just (Name user project)
      _ -> Nothing


fromString' :: String -> ErrorT String IO Name
fromString' string =
    Maybe.maybe (throwError $ errorMsg string) return (fromString string)


instance Binary Name where
    get = Name <$> get <*> get
    put (Name user project) =
        do  put user
            put project


instance FromJSON Name where
    parseJSON (String text) =
        let string = T.unpack text in
        Maybe.maybe (fail $ errorMsg string) return (fromString string)

    parseJSON _ = fail "Project name must be a string."


instance ToJSON Name where
    toJSON name =
        toJSON (toString name)


errorMsg :: String -> String
errorMsg string =
    unlines
    [ "Dependency file has an invalid name: " ++ string
    , "Must have format user/project and match a public github project."
    ]
