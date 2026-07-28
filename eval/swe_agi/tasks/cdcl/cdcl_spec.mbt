///|
declare pub type Model

///|
declare pub type CnfFormula

///|
declare pub fn CnfFormula::eval(self : CnfFormula, model : Model) -> Bool

///|
declare pub type DimacsParser

///|
declare pub fn DimacsParser::parse(source : Bytes) -> CnfFormula raise

///|
pub enum SolveResult {
  Sat(model~ : Model)
  Unsat
}

///|
declare pub fn solve(cnf : CnfFormula) -> SolveResult
