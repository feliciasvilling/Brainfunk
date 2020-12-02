import Control.Monad.State
import Text.Parsec hiding (State)
import GHC.Char
import Data.Char
import System.IO

data Mode = Strict | ByName

data Exp = App Mode Exp Exp | Var String | Lam String Exp

type Env = [(String, Val)]

data Val = Thunk Env Exp | Closure Env String Exp | Inc | Dec | Read | Ask | Tell | ErrorVal String

-- exp =  exp exp | "\" var* "." exp | var "=" exp ";" exp | "(" exp ")" | var
-- var = "<" | ">" | "+" | "-" | "!" | "?" | "@" | alpha*

strip ('(' : cs) = strip' [] cs
  where
    strip' acc [')'] = reverse acc
    strip' acc (c : cs) = strip' (c : acc) cs
    strip' acc [] = reverse acc
strip cs = cs

instance Show Exp where
  show e = strip $ showExp e
    where
      showExp :: Exp -> String
      showExp (App _ (App m a b) c) = "(" ++ strip (showExp $ App m a b) ++ " " ++ showExp c ++ ")"
      showExp (App _ a b) = "(" ++ showExp a ++ " " ++ showExp b ++ ")"
      showExp (Var s) = s
      showExp (Lam v1 (Lam v2 b)) = "(\\" ++ v1 ++ " " ++ tail (strip $ show $ Lam v2 b) ++ ")"
      showExp (Lam v b) = "(\\" ++ v ++ "." ++ strip (show b) ++ ")"

instance Show Val where
  show (Thunk _ exp) = "[" ++ show exp ++ "]"
  show (Closure _ v b) = "\\" ++ v ++ "." ++ strip (show b)
  show Inc = "+"
  show Dec = "-"
  show Ask = "?"
  show Tell = "!"
  show (ErrorVal s) = "error: " ++ s

reserved = "\\.=;() "

alpha = do
  name <- many1 ( oneOf ['0' .. '9'] <|> letter) <?> "alphanumeric"
  return $ Var name

single = do
  name <- noneOf reserved
  return $ Var [name]

variable = alpha <|> single <?> "variable"

parens = do
  char '('
  exp <- expression
  char ')'
  return exp

atom = variable <|> parens

application = do foldl1 app <$>  application' where
    application' = do
        fun <- atom
        spaces
        arg <- try application' <|> do
            a <- atom
            return [a]
        return $ fun : arg

lambda = do
  char '\\'
  vars <- sepBy (many1 letter) spaces
  char '.'
  exp <- expression
  return $ foldr Lam exp vars

declaration = do
  Var var <- variable
  spaces
  char '='
  exp1 <- expression
  char ';'
  exp2 <- expression
  return $ app (Lam var exp2) exp1

expression = do
  spaces
  exp <-  try declaration <|> lambda <|> application <|> parens <?> "expression"
  spaces
  return exp

grammar :: Parsec String () Exp
grammar = expression

eval :: [(String, Val)] -> Exp -> StateT Int IO Val
eval env exp = do
  val <- eval' env exp
  unthunk val

eval' env (Var s) = case lookup s env of
  Just val -> return val
  Nothing -> return $ ErrorVal $ "cant find find variable " ++ s ++ " in environment"
eval' env (Lam var body) = return $ Closure env var body
eval' env (App Strict exp1 exp2) = do
  fun <- eval env exp1
  val2 <- eval' env exp2
  apply fun val2
eval' env (App ByName exp1 exp2) = do
  fun <- eval env exp1
  apply fun $ Thunk env exp2

apply :: Val -> Val -> StateT Int IO Val
apply (Closure env var body) arg = eval ((var, arg) : env) body
apply Inc arg = do
  old <- get
  put $ old + 1
  return arg
apply Dec arg = do
  old <- get
  put $ old - 1
  return arg
apply Read arg = do
  val <- get
  apply (church val) arg
apply Tell arg = do
    n <- get
    liftIO $ putChar $ chr n
    return arg
apply Ask arg = do
    ch <- liftIO getChar
    put $ ord ch
    return arg
apply (ErrorVal e) _ = return $ ErrorVal e
apply _ (ErrorVal e) = return $ ErrorVal e
apply val _ = do
  return $ ErrorVal $ show val ++ " is not a function"

church n = Closure [] "f" $ Lam "x" $ iter n (Var "x")
  where
    iter 0 arg = arg
    iter n arg = app (Var "f") $ iter (n -1) arg

unthunk :: Val -> StateT Int IO Val
unthunk (Thunk env body) = do
  val <- eval' env body
  unthunk val
unthunk val = return val

initialStore = 0

app = App ByName

builtin = [("+", Inc), ("-", Dec), ("@", Read), ("?", Ask), ("!", Tell)]

main = do
  hSetBuffering stdin NoBuffering
  let source = "2=\\f x.f (f x); !!?!?!- "
  let parsed = parse grammar "fuckup" source
  print parsed
  res <- case parsed of
        Right program -> runStateT (eval builtin program) initialStore
        Left error -> return (ErrorVal $ show error, initialStore)
  putChar '\n'
  print res
