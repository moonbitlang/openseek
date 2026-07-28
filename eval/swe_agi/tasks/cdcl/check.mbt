///|
pub fn check_sat(path : String) -> Unit raise {
  let source = @fs.read_file_to_bytes(path)
  let cnf = DimacsParser::parse(source)
  guard solve(cnf) is Sat(model~) else {
    fail("failed to solve \{path}, this is a bug")
  }
  guard cnf.eval(model) else {
    fail("find model but \{path} evaluate to false under it, this is a bug")
  }
}

///|
pub fn check_unsat(path : String) -> Unit raise {
  let source = @fs.read_file_to_bytes(path)
  let cnf = DimacsParser::parse(source)
  guard solve(cnf) is Unsat else {
    fail("\{path} solved but this is a unsat testcase")
  }
}
