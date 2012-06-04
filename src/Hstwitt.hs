import Web.Authenticate.OAuth
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy.Char8 as L
import Network.HTTP.Conduit
import qualified Data.Map as Map
import System.IO
import System.Directory
import Network.Hstwitt.Const
import Network.Hstwitt.Conf
import Network.Hstwitt.Types
import Control.Exception
import Data.Maybe
import Control.Monad.IO.Class (MonadIO (liftIO))
import Data.Aeson
import qualified Data.Conduit as C
import Control.Monad.Trans.Resource
import Graphics.UI.Gtk

twittertest = "http://api.twitter.com/1/statuses/home_timeline.json"

debugGetCred = do
    mconf <- readConf configfile
    let conf = fst $ fromJust mconf
    return $ Credential $ Map.toList conf

test = do
	mconf <- readConf configfile
	let conf = fst $ fromJust mconf
	signedHttp (Credential $ Map.toList conf) twittertest

debugreq :: IO (C.Source (ResourceT IO) B.ByteString)
debugreq = liftIO $ withManager $ \m -> do
        cred <- liftIO $ debugGetCred
        req <- liftIO $ parseUrl twittertest
        surl <- signOAuth oauth cred req
        fmap responseBody $ http surl m


signedHttp :: MonadIO m => Credential -> String -> m L.ByteString
signedHttp cred url = liftIO $ withManager $ \man -> do
        url' <- liftIO $ parseUrl url
        url'' <- signOAuth oauth cred url'
        fmap responseBody $ httpLbs url'' man

main = do
    hSetBuffering stdout NoBuffering -- fixes problems with the output
    conf <- readConf configfile   
    if isNothing conf then 
		auth 
	 else 
                createGUI $ fst $ fromJust conf
	--	tweet $ fst $ fromJust conf

createGUI conf = do
	let cred = Credential $ Map.toList conf
	jsontimeline <- signedHttp cred twittertest
	let timeline = fromJust $ decode jsontimeline  :: Tweets
        initGUI
        window <- windowNew
        vPaned <- vPanedNew
        inputField <- textViewNew
        tweetsScroll <- scrolledWindowNew Nothing Nothing
        tweetsBox <- vBoxNew False 5
        scrolledWindowAddWithViewport tweetsScroll tweetsBox
        set window [ containerChild := vPaned , windowTitle := "HsTwitt" ]
        mapM (addTweet tweetsBox)  timeline
        panedPack1 vPaned tweetsScroll True False
        panedPack2 vPaned inputField False False
        onDestroy window mainQuit
        widgetShowAll window
        mainGUI
    

addTweet :: VBox -> Tweet -> IO ()
addTweet vBox tweet = do
    tweetLabel <- textViewNew
    tagtable <- textTagTableNew
    bold <- textTagNew $ Just "Bold"
    set bold [ textTagFont := "Sans Italic 12" ]
    textTagTableAdd tagtable bold
    textBuffer <- tweet2textBuffer tweet tagtable
--    textBufferSetText textBuffer $ tweet2String tweet
    textViewSetBuffer tweetLabel textBuffer
    textViewSetEditable tweetLabel False
    textViewSetWrapMode tweetLabel WrapWord
    boxPackEnd vBox tweetLabel PackNatural 0

tweet conf = do
	let cred = Credential $ Map.toList conf
	jsontimeline <- signedHttp cred twittertest
	let timeline = fromJust $ decode jsontimeline  :: Tweets
	mapM printtweet $ reverse timeline
	return ()

colorize :: String -> String -> String
colorize c s = "\ESC[" ++ c ++ "m" ++ s ++ "\ESC[m"

tweet2textBuffer :: Tweet -> TextTagTable-> IO TextBuffer
tweet2textBuffer t tagtable = do
                        buffer <- textBufferNew $ Just tagtable
                        istartName <- textBufferGetEndIter buffer
                        mstartName <- textBufferCreateMark buffer Nothing istartName False
                        textBufferInsert buffer istartName $ tuscreen_name $ tuser t
                        iendName <- textBufferGetEndIter buffer
                        mendName <- textBufferCreateMark buffer Nothing iendName False
                        textBufferInsert buffer iendName "\n"
                        startText <- textBufferGetEndIter buffer
                        textBufferInsert buffer startText $ ttext t
                        endText <- textBufferGetEndIter buffer
                        a <- textBufferGetIterAtMark buffer mstartName
                        b <- textBufferGetIterAtMark buffer mendName
                        textBufferApplyTagByName buffer "Bold" a b
                        return buffer
                        

--(tuscreen_name $ tuser t) ++": \n" ++
--		ttext t

printtweet :: Tweet -> IO ()
printtweet t = putStrLn $ 
		colorize "1;30" (tid_str $ t) ++ " " ++
		colorize "1" (tcreated_at $ t) ++ "\n\t" ++
		colorize "1;32" (tuscreen_name $ tuser t) ++": " ++
		ttext t

auth = do    
    putStrLn "Keine Configdatei gefunden oder Configdatei fehlerhaft, bitte den Link klicken"
    credentials <- withManager $ \manager -> getTemporaryCredential oauth manager
    putStrLn $ authorizeUrl oauth credentials
    putStr "Bitte PIN eingeben: "
    pin <- getLine
    let auth = injectVerifier (B.pack pin) credentials
    accessToken <- withManager $ \manager -> getAccessToken oauth auth manager
    writeConf configfile $ Map.fromList $ unCredential accessToken
    putStrLn $ "Config in " ++ configfile ++ " gespeichert"

