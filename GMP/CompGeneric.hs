module CompGeneric where

import CompAS
-- testing Segala
data KDK = KDK deriving Show
test = S (KD (Or (At (K (And (At (S (KD T))) F))) (Or F (At (K F)))))::Segala KDK

-- | extract the modal atoms from a Boole expression
ma :: Eq a => Boole a -> [Boole a]
ma it = 
  case it of
    F           -> []
    T           -> []
    And phi psi -> (ma phi) `List.union` (ma psi)
    Or phi psi  -> (ma phi) `List.union` (ma psi)
    Not phi     -> ma phi
    --M a phi     -> [M a phi]
    At a        -> [At a]

-- subst :: (Logic a b) => Boole a -> Clause a -> Boole a
subst :: Boole a -> c -> Boole b
subst it s =
  case it of
    And phi psi -> And (subst phi s) (subst psi s)
    Or phi psi  -> Or (subst phi s) (subst psi s)
    Not phi     -> Not (subst phi s)
    T           -> T
    F           -> F
{-
phi (Clause (pos, neg))
  | elem phi neg = F
  | elem phi pos = T    
-}

--eval :: Eq a => Boole a -> Bool
eval :: Boole a -> Bool
eval it = 
  case it of
    T           -> True
    F           -> False
    Not phi     -> not (eval phi)
    Or phi psi  -> (eval phi) || (eval psi)
    And phi psi -> (eval phi) && (eval psi)

-- dnf
--allsat :: (Logic a b) => Boole a -> [Clause a]
dnf :: (Eq t, Logic a [Boole t]) => Boole t -> [Clause Int]
dnf phi = filter (\x -> eval (subst phi x)) (clauses (ma phi))

-- cnf
--cnf :: (Logic a b) => Boole a -> [Clause a]
cnf :: (Eq t, Logic a [Boole t]) => Boole t -> [Clause Int]
cnf phi = map (\(Implies x y) -> (Implies y x)) (dnf (Not phi))

-- proof search
-- phi is provable iff all members of its CNF have a provable matching
-- also any matching is in general a cnf and all of its clauses must hold
--provable :: (Logic a b) => Boole a -> Bool
--provable phi = all (\c -> any (all provable) (match c)) (cnf phi)
