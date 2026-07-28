///|
/// Valid-program tests for the C99 parser.
///
/// Each test feeds a C source snippet to `parse(...)`, then compares
/// `CProgram::to_test_json()` against an explicit JSON value.
///
/// The JSON schema is intended to be stable and explicit (type/kind tags, and
/// `{ "Some": ... }` / `{ "None": true }` for option-like fields).
///
/// Note: This file is intentionally verbose because it serves as a precise
/// conformance oracle for AST shape and type information.
///

///|
test "prim expr/identifier as variable" {
  let code =
    #|int foo() { int x = 1; return x; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "x",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "x",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "prim expr/paren int literal" {
  let code =
    #|int foo() { return (1); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Paren",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "prim expr/nested parens" {
  let code =
    #|int foo() { return ((1)); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Paren",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Paren",
                              "expr": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Int",
                                  "value": "1",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "prim expr/paren expr" {
  let code =
    #|int foo() { return (1 + 2); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Paren",
                          "expr": {
                            "type": "AddiExpr",
                            "kind": {
                              "type": "AddiExprKind",
                              "kind": "AddExpr",
                              "lhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Int",
                                  "value": "1",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                              "rhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Int",
                                  "value": "2",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/function call no args" {
  let code =
    #|int bar() { return 1; }
    #|int foo() { return bar(); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "bar",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Int",
                          "value": "1",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "FuncCall",
                          "callee": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "bar",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int ()",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Function",
                                "params": [],
                                "ret": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                                "variadic": false,
                              },
                            },
                          },
                          "args": [],
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/function call with args" {
  let code =
    #|int add(int a, int b) { return a + b; }
    #|int foo() { return add(1, 2); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "add",
            "params": [
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "a",
              },
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "b",
              },
            ],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "AddiExpr",
                        "kind": {
                          "type": "AddiExprKind",
                          "kind": "AddExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "a",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "b",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "FuncCall",
                          "callee": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "add",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int (int a, int b)",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Function",
                                "params": [
                                  {
                                    "type": "Param",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "name": "a",
                                  },
                                  {
                                    "type": "Param",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "name": "b",
                                  },
                                ],
                                "ret": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                                "variadic": false,
                              },
                            },
                          },
                          "args": [
                            {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                            {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "2",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          ],
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/array access" {
  let code =
    #|int foo() { int arr[10]; return arr[2]; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int[static 10]",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Array",
                          "of": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                          "len": "10",
                        },
                      },
                      "name": "arr",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "ArrayAccess",
                          "array": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "arr",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int[static 10]",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Array",
                                "of": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                                "len": "10",
                              },
                            },
                          },
                          "index": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/pointer subscript" {
  let code =
    #|int foo() { int arr[10]; int *p = arr; return p[2]; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int[static 10]",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Array",
                          "of": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                          "len": "10",
                        },
                      },
                      "name": "arr",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int *",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Ptr",
                          "to": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                        },
                      },
                      "name": "p",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Ident",
                                "name": "arr",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int[static 10]",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Array",
                                  "of": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                  "len": "10",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "ArrayAccess",
                          "array": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "p",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int *",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Ptr",
                                "to": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                          },
                          "index": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/member access" {
  let code =
    #|struct Point { int x; int y; };
    #|int foo() { struct Point p; p.x = 1; return p.x; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "TypeDeclaration",
              "ctype": {
                "type": "CType",
                "repr": "struct Point",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": {
                  "type": "CTypeDataKind",
                  "kind": "Struct",
                  "name": "Point",
                  "fields": [
                    {
                      "type": "StructField",
                      "name": "x",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "bit_width": { "None": true },
                    },
                    {
                      "type": "StructField",
                      "name": "y",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "bit_width": { "None": true },
                    },
                  ],
                },
              },
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "struct Point",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Struct",
                          "name": "Point",
                          "fields": [
                            {
                              "type": "StructField",
                              "name": "x",
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                              "bit_width": { "None": true },
                            },
                            {
                              "type": "StructField",
                              "name": "y",
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                              "bit_width": { "None": true },
                            },
                          ],
                        },
                      },
                      "name": "p",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "MemberAccess",
                              "object": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "p",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "struct Point",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Struct",
                                    "name": "Point",
                                    "fields": [
                                      {
                                        "type": "StructField",
                                        "name": "x",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                      {
                                        "type": "StructField",
                                        "name": "y",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                    ],
                                  },
                                },
                              },
                              "field": "x",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "MemberAccess",
                          "object": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "p",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "struct Point",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Struct",
                                "name": "Point",
                                "fields": [
                                  {
                                    "type": "StructField",
                                    "name": "x",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "bit_width": { "None": true },
                                  },
                                  {
                                    "type": "StructField",
                                    "name": "y",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "bit_width": { "None": true },
                                  },
                                ],
                              },
                            },
                          },
                          "field": "x",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/pointer member access" {
  let code =
    #|struct Point { int x; int y; };
    #|int foo() { struct Point p; struct Point *q = &p; q->x = 1; return q->x; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "TypeDeclaration",
              "ctype": {
                "type": "CType",
                "repr": "struct Point",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": {
                  "type": "CTypeDataKind",
                  "kind": "Struct",
                  "name": "Point",
                  "fields": [
                    {
                      "type": "StructField",
                      "name": "x",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "bit_width": { "None": true },
                    },
                    {
                      "type": "StructField",
                      "name": "y",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "bit_width": { "None": true },
                    },
                  ],
                },
              },
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "struct Point",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Struct",
                          "name": "Point",
                          "fields": [
                            {
                              "type": "StructField",
                              "name": "x",
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                              "bit_width": { "None": true },
                            },
                            {
                              "type": "StructField",
                              "name": "y",
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                              "bit_width": { "None": true },
                            },
                          ],
                        },
                      },
                      "name": "p",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "struct Point *",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Ptr",
                          "to": {
                            "type": "CType",
                            "repr": "struct Point",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Struct",
                              "name": "Point",
                              "fields": [
                                {
                                  "type": "StructField",
                                  "name": "x",
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                  "bit_width": { "None": true },
                                },
                                {
                                  "type": "StructField",
                                  "name": "y",
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                  "bit_width": { "None": true },
                                },
                              ],
                            },
                          },
                        },
                      },
                      "name": "q",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "UnaryExpr",
                              "kind": {
                                "type": "UnaryExprKind",
                                "kind": "AddrOf",
                                "expr": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "p",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "struct Point",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Struct",
                                      "name": "Point",
                                      "fields": [
                                        {
                                          "type": "StructField",
                                          "name": "x",
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "int",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Int",
                                            },
                                          },
                                          "bit_width": { "None": true },
                                        },
                                        {
                                          "type": "StructField",
                                          "name": "y",
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "int",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Int",
                                            },
                                          },
                                          "bit_width": { "None": true },
                                        },
                                      ],
                                    },
                                  },
                                },
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "struct Point *",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Ptr",
                                  "to": {
                                    "type": "CType",
                                    "repr": "struct Point",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Struct",
                                      "name": "Point",
                                      "fields": [
                                        {
                                          "type": "StructField",
                                          "name": "x",
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "int",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Int",
                                            },
                                          },
                                          "bit_width": { "None": true },
                                        },
                                        {
                                          "type": "StructField",
                                          "name": "y",
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "int",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Int",
                                            },
                                          },
                                          "bit_width": { "None": true },
                                        },
                                      ],
                                    },
                                  },
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "PtrMemberAccess",
                              "object": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "q",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "struct Point *",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Ptr",
                                    "to": {
                                      "type": "CType",
                                      "repr": "struct Point",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Struct",
                                        "name": "Point",
                                        "fields": [
                                          {
                                            "type": "StructField",
                                            "name": "x",
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                            "bit_width": { "None": true },
                                          },
                                          {
                                            "type": "StructField",
                                            "name": "y",
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                            "bit_width": { "None": true },
                                          },
                                        ],
                                      },
                                    },
                                  },
                                },
                              },
                              "field": "x",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "PtrMemberAccess",
                          "object": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "q",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "struct Point *",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Ptr",
                                "to": {
                                  "type": "CType",
                                  "repr": "struct Point",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Struct",
                                    "name": "Point",
                                    "fields": [
                                      {
                                        "type": "StructField",
                                        "name": "x",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                      {
                                        "type": "StructField",
                                        "name": "y",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                    ],
                                  },
                                },
                              },
                            },
                          },
                          "field": "x",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/post increment" {
  let code =
    #|int foo() { int i = 0; return i++; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "PostInc",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "i",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/post decrement" {
  let code =
    #|int foo() { int i = 0; return i--; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "PostDec",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "i",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/array access with index expr" {
  let code =
    #|int foo() { int arr[10]; return arr[1 + 2]; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int[static 10]",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Array",
                          "of": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                          "len": "10",
                        },
                      },
                      "name": "arr",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "ArrayAccess",
                          "array": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "arr",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int[static 10]",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Array",
                                "of": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                                "len": "10",
                              },
                            },
                          },
                          "index": {
                            "type": "AddiExpr",
                            "kind": {
                              "type": "AddiExprKind",
                              "kind": "AddExpr",
                              "lhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Int",
                                  "value": "1",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                              "rhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Int",
                                  "value": "2",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/post inc on member access" {
  let code =
    #|struct Point { int x; int y; };
    #|int foo() { struct Point p; p.x = 1; return p.x++; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "TypeDeclaration",
              "ctype": {
                "type": "CType",
                "repr": "struct Point",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": {
                  "type": "CTypeDataKind",
                  "kind": "Struct",
                  "name": "Point",
                  "fields": [
                    {
                      "type": "StructField",
                      "name": "x",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "bit_width": { "None": true },
                    },
                    {
                      "type": "StructField",
                      "name": "y",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "bit_width": { "None": true },
                    },
                  ],
                },
              },
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "struct Point",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Struct",
                          "name": "Point",
                          "fields": [
                            {
                              "type": "StructField",
                              "name": "x",
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                              "bit_width": { "None": true },
                            },
                            {
                              "type": "StructField",
                              "name": "y",
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                              "bit_width": { "None": true },
                            },
                          ],
                        },
                      },
                      "name": "p",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "MemberAccess",
                              "object": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "p",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "struct Point",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Struct",
                                    "name": "Point",
                                    "fields": [
                                      {
                                        "type": "StructField",
                                        "name": "x",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                      {
                                        "type": "StructField",
                                        "name": "y",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                    ],
                                  },
                                },
                              },
                              "field": "x",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "PostInc",
                          "expr": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "MemberAccess",
                              "object": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "p",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "struct Point",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Struct",
                                    "name": "Point",
                                    "fields": [
                                      {
                                        "type": "StructField",
                                        "name": "x",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                      {
                                        "type": "StructField",
                                        "name": "y",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                    ],
                                  },
                                },
                              },
                              "field": "x",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "unary expr/pre increment" {
  let code =
    #|int foo() { int i = 0; return ++i; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "PreInc",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "i",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "unary expr/pre decrement" {
  let code =
    #|int foo() { int i = 0; return --i; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "PreDec",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "i",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "unary expr/address of" {
  let code =
    #|int *foo() { int i = 0; return &i; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int *",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": {
                "type": "CTypeDataKind",
                "kind": "Ptr",
                "to": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
              },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "AddrOf",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "i",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int *",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "Ptr",
                            "to": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "unary expr/deref" {
  let code =
    #|int foo() { int i = 1; int *p = &i; return *p; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int *",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Ptr",
                          "to": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                        },
                      },
                      "name": "p",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "UnaryExpr",
                              "kind": {
                                "type": "UnaryExprKind",
                                "kind": "AddrOf",
                                "expr": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "i",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                },
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int *",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Ptr",
                                  "to": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "Deref",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "p",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int *",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Ptr",
                                "to": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "unary expr/negate" {
  let code =
    #|int foo() { return -1; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "Negate",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "unary expr/bitwise not" {
  let code =
    #|int foo() { return ~1; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "BitNot",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "unary expr/logical not" {
  let code =
    #|int foo() { return !0; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "LogicalNot",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "0",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "unary expr/sizeof expr" {
  let code =
    #|long foo() { int x = 0; return sizeof(x); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "long",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Long" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "x",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "SizeofExpr",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Paren",
                              "expr": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "x",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "unsigned long",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "ULong",
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "unary expr/sizeof type" {
  let code =
    #|long foo() { return sizeof(int); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "long",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Long" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "SizeofType",
                          "ctype": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "unsigned long",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "ULong",
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "unary expr/deref post increment" {
  let code =
    #|int foo() { int arr[2]; int *p = arr; return *(p++); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int[static 2]",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Array",
                          "of": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                          "len": "2",
                        },
                      },
                      "name": "arr",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int *",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Ptr",
                          "to": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                        },
                      },
                      "name": "p",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Ident",
                                "name": "arr",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int[static 2]",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Array",
                                  "of": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                  "len": "2",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "Deref",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Paren",
                              "expr": {
                                "type": "PostfixExpr",
                                "kind": {
                                  "type": "PostfixExprKind",
                                  "kind": "PostInc",
                                  "expr": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Ident",
                                      "name": "p",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int *",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Ptr",
                                        "to": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int *",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Ptr",
                                    "to": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int *",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Ptr",
                                "to": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "cast expr/int from double" {
  let code =
    #|int foo() { return (int)3.14; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "CastExpr",
                        "kind": {
                          "type": "CastExprKind",
                          "kind": "CastTo",
                          "ctype": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Double",
                              "value": "3.14",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "double",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Double",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "cast expr/float from int" {
  let code =
    #|float foo() { return (float)1; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "float",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Float" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "CastExpr",
                        "kind": {
                          "type": "CastExprKind",
                          "kind": "CastTo",
                          "ctype": {
                            "type": "CType",
                            "repr": "float",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Float",
                            },
                          },
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "float",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "Float",
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "cast expr/pointer cast" {
  let code =
    #|char *foo() { int i = 0; int *p = &i; return (char *)p; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "char *",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": {
                "type": "CTypeDataKind",
                "kind": "Ptr",
                "to": {
                  "type": "CType",
                  "repr": "char",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Char" },
                },
              },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int *",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Ptr",
                          "to": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                        },
                      },
                      "name": "p",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "UnaryExpr",
                              "kind": {
                                "type": "UnaryExprKind",
                                "kind": "AddrOf",
                                "expr": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "i",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                },
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int *",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Ptr",
                                  "to": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "CastExpr",
                        "kind": {
                          "type": "CastExprKind",
                          "kind": "CastTo",
                          "ctype": {
                            "type": "CType",
                            "repr": "char *",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Ptr",
                              "to": {
                                "type": "CType",
                                "repr": "char",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Char",
                                },
                              },
                            },
                          },
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "p",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int *",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Ptr",
                                "to": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "char *",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "Ptr",
                            "to": {
                              "type": "CType",
                              "repr": "char",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Char",
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "cast expr/nested cast" {
  let code =
    #|long foo() { return (long)(int)3.14; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "long",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Long" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "CastExpr",
                        "kind": {
                          "type": "CastExprKind",
                          "kind": "CastTo",
                          "ctype": {
                            "type": "CType",
                            "repr": "long",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Long",
                            },
                          },
                          "expr": {
                            "type": "CastExpr",
                            "kind": {
                              "type": "CastExprKind",
                              "kind": "CastTo",
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                              "expr": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Double",
                                  "value": "3.14",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "double",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Double",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "long",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "Long",
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "multi expr/mul" {
  let code =
    #|int foo() { return 2 * 3; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "MultiExpr",
                        "kind": {
                          "type": "MultiExprKind",
                          "kind": "MulExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "3",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "multi expr/div" {
  let code =
    #|int foo() { return 4 / 2; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "MultiExpr",
                        "kind": {
                          "type": "MultiExprKind",
                          "kind": "DivExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "4",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "multi expr/mod" {
  let code =
    #|int foo() { return 5 % 2; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "MultiExpr",
                        "kind": {
                          "type": "MultiExprKind",
                          "kind": "ModExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "5",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "addi expr/add" {
  let code =
    #|int foo() { return 1 + 2; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "AddiExpr",
                        "kind": {
                          "type": "AddiExprKind",
                          "kind": "AddExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "addi expr/sub" {
  let code =
    #|int foo() { return 5 - 3; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "AddiExpr",
                        "kind": {
                          "type": "AddiExprKind",
                          "kind": "SubExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "5",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "3",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "shift expr/shl" {
  let code =
    #|int foo() { return 1 << 2; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "ShiftExpr",
                        "kind": {
                          "type": "ShiftExprKind",
                          "kind": "ShlExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "shift expr/shr" {
  let code =
    #|int foo() { return 8 >> 1; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "ShiftExpr",
                        "kind": {
                          "type": "ShiftExprKind",
                          "kind": "ShrExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "8",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "relational expr/lt" {
  let code =
    #|int foo() { return 1 < 2; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "RelationalExpr",
                        "kind": {
                          "type": "RelationalExprKind",
                          "kind": "LTExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "relational expr/ge" {
  let code =
    #|int foo() { return 2 >= 1; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "RelationalExpr",
                        "kind": {
                          "type": "RelationalExprKind",
                          "kind": "GEExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "equality expr/eq" {
  let code =
    #|int foo() { return 1 == 2; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "EqualityExpr",
                        "kind": {
                          "type": "EqualityExprKind",
                          "kind": "EQExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "equality expr/ne" {
  let code =
    #|int foo() { return 1 != 2; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "EqualityExpr",
                        "kind": {
                          "type": "EqualityExprKind",
                          "kind": "NEExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "bitwise and expr" {
  let code =
    #|int foo() { return 1 & 2; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "AndExpr",
                        "kind": {
                          "type": "AndExprKind",
                          "kind": "AndExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "bitwise xor expr" {
  let code =
    #|int foo() { return 1 ^ 2; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "ExclusiveOrExpr",
                        "kind": {
                          "type": "ExclusiveOrExprKind",
                          "kind": "ExclusiveOrExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "bitwise or expr" {
  let code =
    #|int foo() { return 1 | 2; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "InclusiveOrExpr",
                        "kind": {
                          "type": "InclusiveOrExprKind",
                          "kind": "InclusiveOrExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "logical and expr" {
  let code =
    #|int foo() { return 1 && 0; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "LogicalAndExpr",
                        "kind": {
                          "type": "LogicalAndExprKind",
                          "kind": "LogicalAndExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "0",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "logical or expr" {
  let code =
    #|int foo() { return 1 || 0; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "LogicalOrExpr",
                        "kind": {
                          "type": "LogicalOrExprKind",
                          "kind": "LogicalOrExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "0",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "conditional expr/simple" {
  let code =
    #|int foo() { return 1 ? 2 : 3; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "ConditionalExpr",
                        "kind": {
                          "type": "ConditionalExprKind",
                          "kind": "ConditionalExpr",
                          "cond": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "then": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "else": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "3",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "conditional expr/nested" {
  let code =
    #|int foo() { return 1 ? (2 ? 3 : 4) : 5; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "ConditionalExpr",
                        "kind": {
                          "type": "ConditionalExprKind",
                          "kind": "ConditionalExpr",
                          "cond": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "then": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Paren",
                              "expr": {
                                "type": "ConditionalExpr",
                                "kind": {
                                  "type": "ConditionalExprKind",
                                  "kind": "ConditionalExpr",
                                  "cond": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Int",
                                      "value": "2",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                  "then": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Int",
                                      "value": "3",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                  "else": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Int",
                                      "value": "4",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "else": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "5",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "assign expr/simple assign" {
  let code =
    #|int foo() { int a = 0; a = 1; return a; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "a",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "a",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "a",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "assign expr/compound add assign" {
  let code =
    #|int foo() { int a = 0; a += 1; return a; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "a",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "a",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "+=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "a",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "assign expr/compound shl assign" {
  let code =
    #|int foo() { int a = 1; a <<= 2; return a; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "a",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "a",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "<<=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "a",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "assign expr/deref assign" {
  let code =
    #|int foo() { int a = 0; int *p = &a; *p = 1; return a; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "a",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int *",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Ptr",
                          "to": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                        },
                      },
                      "name": "p",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "UnaryExpr",
                              "kind": {
                                "type": "UnaryExprKind",
                                "kind": "AddrOf",
                                "expr": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "a",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                },
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int *",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Ptr",
                                  "to": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "UnaryExpr",
                            "kind": {
                              "type": "UnaryExprKind",
                              "kind": "Deref",
                              "expr": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "p",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int *",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Ptr",
                                    "to": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "a",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "assign expr/array element assign" {
  let code =
    #|int foo() { int arr[3]; arr[0] = 1; return arr[0]; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int[static 3]",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Array",
                          "of": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                          "len": "3",
                        },
                      },
                      "name": "arr",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "ArrayAccess",
                              "array": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "arr",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int[static 3]",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Array",
                                    "of": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "len": "3",
                                  },
                                },
                              },
                              "index": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Int",
                                  "value": "0",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "ArrayAccess",
                          "array": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "arr",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int[static 3]",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Array",
                                "of": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                                "len": "3",
                              },
                            },
                          },
                          "index": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "0",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "expr/comma with assignments" {
  let code =
    #|int foo() { int a = 0; int b = 0; return (a = 1, b = 2); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "a",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "b",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Paren",
                          "expr": {
                            "type": "Expr",
                            "kind": "Comma",
                            "items": [
                              {
                                "type": "AssignExpr",
                                "kind": {
                                  "type": "AssignExprKind",
                                  "kind": "Assign",
                                  "lhs": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Ident",
                                      "name": "a",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                  "op": { "type": "AssignOp", "op": "=" },
                                  "rhs": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Int",
                                      "value": "1",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                              {
                                "type": "AssignExpr",
                                "kind": {
                                  "type": "AssignExprKind",
                                  "kind": "Assign",
                                  "lhs": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Ident",
                                      "name": "b",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                  "op": { "type": "AssignOp", "op": "=" },
                                  "rhs": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Int",
                                      "value": "2",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            ],
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "expr/comma with post increments" {
  let code =
    #|int foo() { int i = 0; int j = 0; return (i++, j++); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "j",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Paren",
                          "expr": {
                            "type": "Expr",
                            "kind": "Comma",
                            "items": [
                              {
                                "type": "PostfixExpr",
                                "kind": {
                                  "type": "PostfixExprKind",
                                  "kind": "PostInc",
                                  "expr": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Ident",
                                      "name": "i",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                              {
                                "type": "PostfixExpr",
                                "kind": {
                                  "type": "PostfixExprKind",
                                  "kind": "PostInc",
                                  "expr": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Ident",
                                      "name": "j",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            ],
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "stmt/if else" {
  let code =
    #|int foo(int x) { if (x) return 1; else return 0; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "x",
              },
            ],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "If",
                      "stmt": {
                        "type": "IfStmt",
                        "cond": {
                          "type": "PrimExpr",
                          "kind": {
                            "type": "PrimExprKind",
                            "kind": "Ident",
                            "name": "x",
                          },
                          "ctype": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                        },
                        "then": {
                          "type": "Statement",
                          "kind": {
                            "type": "StmtKind",
                            "kind": "Return",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                        "else": {
                          "Some": {
                            "type": "Statement",
                            "kind": {
                              "type": "StmtKind",
                              "kind": "Return",
                              "expr": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Int",
                                  "value": "0",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "stmt/while" {
  let code =
    #|int foo() { int i = 0; while (i < 3) { i++; } return i; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "While",
                      "stmt": {
                        "type": "WhileStmt",
                        "cond": {
                          "type": "RelationalExpr",
                          "kind": {
                            "type": "RelationalExprKind",
                            "kind": "LTExpr",
                            "lhs": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Ident",
                                "name": "i",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                            "rhs": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "3",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                          "ctype": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                        },
                        "body": {
                          "type": "Statement",
                          "kind": {
                            "type": "StmtKind",
                            "kind": "Compound",
                            "body": {
                              "type": "CompoundStmt",
                              "items": [
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Expr",
                                      "expr": {
                                        "type": "PostfixExpr",
                                        "kind": {
                                          "type": "PostfixExprKind",
                                          "kind": "PostInc",
                                          "expr": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "i",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              ],
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "i",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "stmt/do while" {
  let code =
    #|int foo() { int i = 0; do { i++; } while (i < 3); return i; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "DoWhile",
                      "stmt": {
                        "type": "DoWhileStmt",
                        "body": {
                          "type": "Statement",
                          "kind": {
                            "type": "StmtKind",
                            "kind": "Compound",
                            "body": {
                              "type": "CompoundStmt",
                              "items": [
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Expr",
                                      "expr": {
                                        "type": "PostfixExpr",
                                        "kind": {
                                          "type": "PostfixExprKind",
                                          "kind": "PostInc",
                                          "expr": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "i",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              ],
                            },
                          },
                        },
                        "cond": {
                          "type": "RelationalExpr",
                          "kind": {
                            "type": "RelationalExprKind",
                            "kind": "LTExpr",
                            "lhs": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Ident",
                                "name": "i",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                            "rhs": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "3",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                          "ctype": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "i",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "stmt/for with decl init" {
  let code =
    #|int foo() { int sum = 0; for (int i = 0; i < 3; i++) { sum += i; } return sum; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "sum",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "For",
                      "stmt": {
                        "type": "ForStmt",
                        "init": {
                          "Some": {
                            "type": "ForInit",
                            "kind": "Declaration",
                            "decls": [
                              {
                                "type": "Declaration",
                                "kind": {
                                  "type": "DeclarationKind",
                                  "kind": "VariableDeclaration",
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                  "name": "i",
                                  "storage": {
                                    "static": false,
                                    "extern": false,
                                    "register": false,
                                    "thread_local": false,
                                  },
                                  "init": {
                                    "Some": {
                                      "type": "Initializer",
                                      "kind": {
                                        "type": "InitializerKind",
                                        "kind": "AssignExpr",
                                        "expr": {
                                          "type": "PrimExpr",
                                          "kind": {
                                            "type": "PrimExprKind",
                                            "kind": "Int",
                                            "value": "0",
                                          },
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "int",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Int",
                                            },
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              },
                            ],
                          },
                        },
                        "cond": {
                          "Some": {
                            "type": "RelationalExpr",
                            "kind": {
                              "type": "RelationalExprKind",
                              "kind": "LTExpr",
                              "lhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "i",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                              "rhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Int",
                                  "value": "3",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "update": {
                          "Some": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "PostInc",
                              "expr": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "i",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "body": {
                          "type": "Statement",
                          "kind": {
                            "type": "StmtKind",
                            "kind": "Compound",
                            "body": {
                              "type": "CompoundStmt",
                              "items": [
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Expr",
                                      "expr": {
                                        "type": "AssignExpr",
                                        "kind": {
                                          "type": "AssignExprKind",
                                          "kind": "Assign",
                                          "lhs": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "sum",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                          "op": {
                                            "type": "AssignOp",
                                            "op": "+=",
                                          },
                                          "rhs": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "i",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              ],
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "sum",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "stmt/switch" {
  let code =
    #|int foo(int x) {
    #|  switch (x) {
    #|    case 0: return 1;
    #|    case 1: return 2;
    #|    default: return 3;
    #|  }
    #|}
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "x",
              },
            ],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Switch",
                      "stmt": {
                        "type": "SwitchStmt",
                        "expr": {
                          "type": "PrimExpr",
                          "kind": {
                            "type": "PrimExprKind",
                            "kind": "Ident",
                            "name": "x",
                          },
                          "ctype": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                        },
                        "body": {
                          "type": "Statement",
                          "kind": {
                            "type": "StmtKind",
                            "kind": "Compound",
                            "body": {
                              "type": "CompoundStmt",
                              "items": [
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Case",
                                      "expr": {
                                        "type": "PrimExpr",
                                        "kind": {
                                          "type": "PrimExprKind",
                                          "kind": "Int",
                                          "value": "0",
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                      "stmt": {
                                        "type": "Statement",
                                        "kind": {
                                          "type": "StmtKind",
                                          "kind": "Return",
                                          "expr": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Int",
                                              "value": "1",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Case",
                                      "expr": {
                                        "type": "PrimExpr",
                                        "kind": {
                                          "type": "PrimExprKind",
                                          "kind": "Int",
                                          "value": "1",
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                      "stmt": {
                                        "type": "Statement",
                                        "kind": {
                                          "type": "StmtKind",
                                          "kind": "Return",
                                          "expr": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Int",
                                              "value": "2",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "DefaultCase",
                                      "stmt": {
                                        "type": "Statement",
                                        "kind": {
                                          "type": "StmtKind",
                                          "kind": "Return",
                                          "expr": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Int",
                                              "value": "3",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              ],
                            },
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "stmt/goto and label" {
  let code =
    #|int foo() { int x = 0; goto L; x = 1; L: return x; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "x",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": { "type": "StmtKind", "kind": "Goto", "label": "L" },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "x",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Labeled",
                      "name": "L",
                      "stmt": {
                        "type": "Statement",
                        "kind": {
                          "type": "StmtKind",
                          "kind": "Return",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "x",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "prim expr/escape string \\n\\t\\r" {
  let code =
    #|const char *foo() { return "\n\t\r"; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "const char *",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": {
                "type": "CTypeDataKind",
                "kind": "Ptr",
                "to": {
                  "type": "CType",
                  "repr": "const char",
                  "qualifiers": {
                    "const": true,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Char" },
                },
              },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Strings",
                          "value": ["\n\t\r"],
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "const char *",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "Ptr",
                            "to": {
                              "type": "CType",
                              "repr": "const char",
                              "qualifiers": {
                                "const": true,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Char",
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "prim expr/escape string quote" {
  let code =
    #|const char *foo() { return "he\"llo"; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "const char *",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": {
                "type": "CTypeDataKind",
                "kind": "Ptr",
                "to": {
                  "type": "CType",
                  "repr": "const char",
                  "qualifiers": {
                    "const": true,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Char" },
                },
              },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Strings",
                          "value": ["he\"llo"],
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "const char *",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "Ptr",
                            "to": {
                              "type": "CType",
                              "repr": "const char",
                              "qualifiers": {
                                "const": true,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Char",
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "prim expr/escape string backslash" {
  let code =
    #|const char *foo() { return "C:\\path\\file"; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "const char *",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": {
                "type": "CTypeDataKind",
                "kind": "Ptr",
                "to": {
                  "type": "CType",
                  "repr": "const char",
                  "qualifiers": {
                    "const": true,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Char" },
                },
              },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Strings",
                          "value": ["C:\\path\\file"],
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "const char *",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "Ptr",
                            "to": {
                              "type": "CType",
                              "repr": "const char",
                              "qualifiers": {
                                "const": true,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Char",
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "prim expr/escape char \\n" {
  let code =
    #|int foo() { return '\n'; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Char",
                          "value": "\n",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "char",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "Char",
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "prim expr/escape char \\\\" {
  let code =
    #|int foo() { return '\\'; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Char",
                          "value": "\\",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "char",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "Char",
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "prim expr/negative int literal" {
  let code =
    #|int foo() { return -42; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "Negate",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "42",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "prim expr/double negative" {
  let code =
    #|int foo() { return -(-1); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "Negate",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Paren",
                              "expr": {
                                "type": "UnaryExpr",
                                "kind": {
                                  "type": "UnaryExprKind",
                                  "kind": "Negate",
                                  "expr": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Int",
                                      "value": "1",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "prim expr/mixed paren and postfix" {
  let code =
    #|int bar() { return 1; }
    #|int foo() { return (bar)(); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "bar",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Int",
                          "value": "1",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "FuncCall",
                          "callee": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Paren",
                              "expr": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "bar",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int ()",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Function",
                                    "params": [],
                                    "ret": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "variadic": false,
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int ()",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Function",
                                "params": [],
                                "ret": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                                "variadic": false,
                              },
                            },
                          },
                          "args": [],
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/arr_i_postinc" {
  let code =
    #|int foo() { int arr[3]; int i = 0; return arr[i]++; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int[static 3]",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Array",
                          "of": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                          "len": "3",
                        },
                      },
                      "name": "arr",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "PostInc",
                          "expr": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "ArrayAccess",
                              "array": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "arr",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int[static 3]",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Array",
                                    "of": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "len": "3",
                                  },
                                },
                              },
                              "index": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "i",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/arr_postinc_index" {
  let code =
    #|int foo() { int arr[3]; int i = 0; return arr[i++]; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int[static 3]",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Array",
                          "of": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                          "len": "3",
                        },
                      },
                      "name": "arr",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "ArrayAccess",
                          "array": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "arr",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int[static 3]",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Array",
                                "of": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                                "len": "3",
                              },
                            },
                          },
                          "index": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "PostInc",
                              "expr": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "i",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/nested calls" {
  let code =
    #|int add(int a, int b) { return a + b; }
    #|int foo() { return add(add(1, 2), add(3, 4)); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "add",
            "params": [
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "a",
              },
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "b",
              },
            ],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "AddiExpr",
                        "kind": {
                          "type": "AddiExprKind",
                          "kind": "AddExpr",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "a",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "b",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "FuncCall",
                          "callee": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "add",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int (int a, int b)",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Function",
                                "params": [
                                  {
                                    "type": "Param",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "name": "a",
                                  },
                                  {
                                    "type": "Param",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "name": "b",
                                  },
                                ],
                                "ret": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                                "variadic": false,
                              },
                            },
                          },
                          "args": [
                            {
                              "type": "PostfixExpr",
                              "kind": {
                                "type": "PostfixExprKind",
                                "kind": "FuncCall",
                                "callee": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "add",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int (int a, int b)",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Function",
                                      "params": [
                                        {
                                          "type": "Param",
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "int",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Int",
                                            },
                                          },
                                          "name": "a",
                                        },
                                        {
                                          "type": "Param",
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "int",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Int",
                                            },
                                          },
                                          "name": "b",
                                        },
                                      ],
                                      "ret": {
                                        "type": "CType",
                                        "repr": "int",
                                        "qualifiers": {
                                          "const": false,
                                          "volatile": false,
                                          "restrict": false,
                                          "atomic": false,
                                        },
                                        "dataKind": {
                                          "type": "CTypeDataKind",
                                          "kind": "Int",
                                        },
                                      },
                                      "variadic": false,
                                    },
                                  },
                                },
                                "args": [
                                  {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Int",
                                      "value": "1",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                  {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Int",
                                      "value": "2",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                ],
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                            {
                              "type": "PostfixExpr",
                              "kind": {
                                "type": "PostfixExprKind",
                                "kind": "FuncCall",
                                "callee": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "add",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int (int a, int b)",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Function",
                                      "params": [
                                        {
                                          "type": "Param",
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "int",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Int",
                                            },
                                          },
                                          "name": "a",
                                        },
                                        {
                                          "type": "Param",
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "int",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Int",
                                            },
                                          },
                                          "name": "b",
                                        },
                                      ],
                                      "ret": {
                                        "type": "CType",
                                        "repr": "int",
                                        "qualifiers": {
                                          "const": false,
                                          "volatile": false,
                                          "restrict": false,
                                          "atomic": false,
                                        },
                                        "dataKind": {
                                          "type": "CTypeDataKind",
                                          "kind": "Int",
                                        },
                                      },
                                      "variadic": false,
                                    },
                                  },
                                },
                                "args": [
                                  {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Int",
                                      "value": "3",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                  {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Int",
                                      "value": "4",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                ],
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          ],
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/many args call" {
  let code =
    #|int f(int a, int b, int c, int d, int e, int g) { return a + b + c + d + e + g; }
    #|int foo() { return f(1, 2, 3, 4, 5, 6); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "f",
            "params": [
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "a",
              },
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "b",
              },
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "c",
              },
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "d",
              },
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "e",
              },
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "g",
              },
            ],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "AddiExpr",
                        "kind": {
                          "type": "AddiExprKind",
                          "kind": "AddExpr",
                          "lhs": {
                            "type": "AddiExpr",
                            "kind": {
                              "type": "AddiExprKind",
                              "kind": "AddExpr",
                              "lhs": {
                                "type": "AddiExpr",
                                "kind": {
                                  "type": "AddiExprKind",
                                  "kind": "AddExpr",
                                  "lhs": {
                                    "type": "AddiExpr",
                                    "kind": {
                                      "type": "AddiExprKind",
                                      "kind": "AddExpr",
                                      "lhs": {
                                        "type": "AddiExpr",
                                        "kind": {
                                          "type": "AddiExprKind",
                                          "kind": "AddExpr",
                                          "lhs": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "a",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                          "rhs": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "b",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                      "rhs": {
                                        "type": "PrimExpr",
                                        "kind": {
                                          "type": "PrimExprKind",
                                          "kind": "Ident",
                                          "name": "c",
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                  "rhs": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Ident",
                                      "name": "d",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                  },
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                              "rhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "e",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "g",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "FuncCall",
                          "callee": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "f",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int (int a, int b, int c, int d, int e, int g)",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Function",
                                "params": [
                                  {
                                    "type": "Param",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "name": "a",
                                  },
                                  {
                                    "type": "Param",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "name": "b",
                                  },
                                  {
                                    "type": "Param",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "name": "c",
                                  },
                                  {
                                    "type": "Param",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "name": "d",
                                  },
                                  {
                                    "type": "Param",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "name": "e",
                                  },
                                  {
                                    "type": "Param",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "name": "g",
                                  },
                                ],
                                "ret": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                                "variadic": false,
                              },
                            },
                          },
                          "args": [
                            {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                            {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "2",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                            {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "3",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                            {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "4",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                            {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "5",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                            {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "6",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          ],
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/variadic decl and call" {
  let code =
    #|int printf(const char *fmt, ...);
    #|int foo() { return printf("x=%d\\n", 1); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "VariableDeclaration",
              "ctype": {
                "type": "CType",
                "repr": "int (const char * fmt, ...)",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": {
                  "type": "CTypeDataKind",
                  "kind": "Function",
                  "params": [
                    {
                      "type": "Param",
                      "ctype": {
                        "type": "CType",
                        "repr": "const char *",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Ptr",
                          "to": {
                            "type": "CType",
                            "repr": "const char",
                            "qualifiers": {
                              "const": true,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Char",
                            },
                          },
                        },
                      },
                      "name": "fmt",
                    },
                  ],
                  "ret": {
                    "type": "CType",
                    "repr": "int",
                    "qualifiers": {
                      "const": false,
                      "volatile": false,
                      "restrict": false,
                      "atomic": false,
                    },
                    "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                  },
                  "variadic": true,
                },
              },
              "name": "printf",
              "storage": {
                "static": false,
                "extern": false,
                "register": false,
                "thread_local": false,
              },
              "init": { "None": true },
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "FuncCall",
                          "callee": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "printf",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int (const char * fmt, ...)",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Function",
                                "params": [
                                  {
                                    "type": "Param",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "const char *",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Ptr",
                                        "to": {
                                          "type": "CType",
                                          "repr": "const char",
                                          "qualifiers": {
                                            "const": true,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Char",
                                          },
                                        },
                                      },
                                    },
                                    "name": "fmt",
                                  },
                                ],
                                "ret": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                                "variadic": true,
                              },
                            },
                          },
                          "args": [
                            {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Strings",
                                "value": ["x=%d\\n"],
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "const char *",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Ptr",
                                  "to": {
                                    "type": "CType",
                                    "repr": "const char",
                                    "qualifiers": {
                                      "const": true,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Char",
                                    },
                                  },
                                },
                              },
                            },
                            {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          ],
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/chained member access w.p.x" {
  let code =
    #|struct Point { int x; int y; };
    #|struct Wrap { struct Point p; };
    #|int foo() { struct Wrap w; w.p.x = 1; return w.p.x; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "TypeDeclaration",
              "ctype": {
                "type": "CType",
                "repr": "struct Point",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": {
                  "type": "CTypeDataKind",
                  "kind": "Struct",
                  "name": "Point",
                  "fields": [
                    {
                      "type": "StructField",
                      "name": "x",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "bit_width": { "None": true },
                    },
                    {
                      "type": "StructField",
                      "name": "y",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "bit_width": { "None": true },
                    },
                  ],
                },
              },
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "TypeDeclaration",
              "ctype": {
                "type": "CType",
                "repr": "struct Wrap",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": {
                  "type": "CTypeDataKind",
                  "kind": "Struct",
                  "name": "Wrap",
                  "fields": [
                    {
                      "type": "StructField",
                      "name": "p",
                      "ctype": {
                        "type": "CType",
                        "repr": "struct Point",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Struct",
                          "name": "Point",
                          "fields": [
                            {
                              "type": "StructField",
                              "name": "x",
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                              "bit_width": { "None": true },
                            },
                            {
                              "type": "StructField",
                              "name": "y",
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                              "bit_width": { "None": true },
                            },
                          ],
                        },
                      },
                      "bit_width": { "None": true },
                    },
                  ],
                },
              },
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "struct Wrap",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Struct",
                          "name": "Wrap",
                          "fields": [
                            {
                              "type": "StructField",
                              "name": "p",
                              "ctype": {
                                "type": "CType",
                                "repr": "struct Point",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Struct",
                                  "name": "Point",
                                  "fields": [
                                    {
                                      "type": "StructField",
                                      "name": "x",
                                      "ctype": {
                                        "type": "CType",
                                        "repr": "int",
                                        "qualifiers": {
                                          "const": false,
                                          "volatile": false,
                                          "restrict": false,
                                          "atomic": false,
                                        },
                                        "dataKind": {
                                          "type": "CTypeDataKind",
                                          "kind": "Int",
                                        },
                                      },
                                      "bit_width": { "None": true },
                                    },
                                    {
                                      "type": "StructField",
                                      "name": "y",
                                      "ctype": {
                                        "type": "CType",
                                        "repr": "int",
                                        "qualifiers": {
                                          "const": false,
                                          "volatile": false,
                                          "restrict": false,
                                          "atomic": false,
                                        },
                                        "dataKind": {
                                          "type": "CTypeDataKind",
                                          "kind": "Int",
                                        },
                                      },
                                      "bit_width": { "None": true },
                                    },
                                  ],
                                },
                              },
                              "bit_width": { "None": true },
                            },
                          ],
                        },
                      },
                      "name": "w",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "MemberAccess",
                              "object": {
                                "type": "PostfixExpr",
                                "kind": {
                                  "type": "PostfixExprKind",
                                  "kind": "MemberAccess",
                                  "object": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Ident",
                                      "name": "w",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "struct Wrap",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Struct",
                                        "name": "Wrap",
                                        "fields": [
                                          {
                                            "type": "StructField",
                                            "name": "p",
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "struct Point",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Struct",
                                                "name": "Point",
                                                "fields": [
                                                  {
                                                    "type": "StructField",
                                                    "name": "x",
                                                    "ctype": {
                                                      "type": "CType",
                                                      "repr": "int",
                                                      "qualifiers": {
                                                        "const": false,
                                                        "volatile": false,
                                                        "restrict": false,
                                                        "atomic": false,
                                                      },
                                                      "dataKind": {
                                                        "type": "CTypeDataKind",
                                                        "kind": "Int",
                                                      },
                                                    },
                                                    "bit_width": {
                                                      "None": true,
                                                    },
                                                  },
                                                  {
                                                    "type": "StructField",
                                                    "name": "y",
                                                    "ctype": {
                                                      "type": "CType",
                                                      "repr": "int",
                                                      "qualifiers": {
                                                        "const": false,
                                                        "volatile": false,
                                                        "restrict": false,
                                                        "atomic": false,
                                                      },
                                                      "dataKind": {
                                                        "type": "CTypeDataKind",
                                                        "kind": "Int",
                                                      },
                                                    },
                                                    "bit_width": {
                                                      "None": true,
                                                    },
                                                  },
                                                ],
                                              },
                                            },
                                            "bit_width": { "None": true },
                                          },
                                        ],
                                      },
                                    },
                                  },
                                  "field": "p",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "struct Point",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Struct",
                                    "name": "Point",
                                    "fields": [
                                      {
                                        "type": "StructField",
                                        "name": "x",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                      {
                                        "type": "StructField",
                                        "name": "y",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                    ],
                                  },
                                },
                              },
                              "field": "x",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "MemberAccess",
                          "object": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "MemberAccess",
                              "object": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "w",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "struct Wrap",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Struct",
                                    "name": "Wrap",
                                    "fields": [
                                      {
                                        "type": "StructField",
                                        "name": "p",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "struct Point",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Struct",
                                            "name": "Point",
                                            "fields": [
                                              {
                                                "type": "StructField",
                                                "name": "x",
                                                "ctype": {
                                                  "type": "CType",
                                                  "repr": "int",
                                                  "qualifiers": {
                                                    "const": false,
                                                    "volatile": false,
                                                    "restrict": false,
                                                    "atomic": false,
                                                  },
                                                  "dataKind": {
                                                    "type": "CTypeDataKind",
                                                    "kind": "Int",
                                                  },
                                                },
                                                "bit_width": { "None": true },
                                              },
                                              {
                                                "type": "StructField",
                                                "name": "y",
                                                "ctype": {
                                                  "type": "CType",
                                                  "repr": "int",
                                                  "qualifiers": {
                                                    "const": false,
                                                    "volatile": false,
                                                    "restrict": false,
                                                    "atomic": false,
                                                  },
                                                  "dataKind": {
                                                    "type": "CTypeDataKind",
                                                    "kind": "Int",
                                                  },
                                                },
                                                "bit_width": { "None": true },
                                              },
                                            ],
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                    ],
                                  },
                                },
                              },
                              "field": "p",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "struct Point",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Struct",
                                "name": "Point",
                                "fields": [
                                  {
                                    "type": "StructField",
                                    "name": "x",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "bit_width": { "None": true },
                                  },
                                  {
                                    "type": "StructField",
                                    "name": "y",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "bit_width": { "None": true },
                                  },
                                ],
                              },
                            },
                          },
                          "field": "x",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "postfix expr/chained ptr member access q->p.x" {
  let code =
    #|struct Point { int x; int y; };
    #|struct Wrap { struct Point p; };
    #|int foo() { struct Wrap w; struct Wrap *q = &w; q->p.x = 1; return q->p.x; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "TypeDeclaration",
              "ctype": {
                "type": "CType",
                "repr": "struct Point",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": {
                  "type": "CTypeDataKind",
                  "kind": "Struct",
                  "name": "Point",
                  "fields": [
                    {
                      "type": "StructField",
                      "name": "x",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "bit_width": { "None": true },
                    },
                    {
                      "type": "StructField",
                      "name": "y",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "bit_width": { "None": true },
                    },
                  ],
                },
              },
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "TypeDeclaration",
              "ctype": {
                "type": "CType",
                "repr": "struct Wrap",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": {
                  "type": "CTypeDataKind",
                  "kind": "Struct",
                  "name": "Wrap",
                  "fields": [
                    {
                      "type": "StructField",
                      "name": "p",
                      "ctype": {
                        "type": "CType",
                        "repr": "struct Point",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Struct",
                          "name": "Point",
                          "fields": [
                            {
                              "type": "StructField",
                              "name": "x",
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                              "bit_width": { "None": true },
                            },
                            {
                              "type": "StructField",
                              "name": "y",
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                              "bit_width": { "None": true },
                            },
                          ],
                        },
                      },
                      "bit_width": { "None": true },
                    },
                  ],
                },
              },
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "struct Wrap",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Struct",
                          "name": "Wrap",
                          "fields": [
                            {
                              "type": "StructField",
                              "name": "p",
                              "ctype": {
                                "type": "CType",
                                "repr": "struct Point",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Struct",
                                  "name": "Point",
                                  "fields": [
                                    {
                                      "type": "StructField",
                                      "name": "x",
                                      "ctype": {
                                        "type": "CType",
                                        "repr": "int",
                                        "qualifiers": {
                                          "const": false,
                                          "volatile": false,
                                          "restrict": false,
                                          "atomic": false,
                                        },
                                        "dataKind": {
                                          "type": "CTypeDataKind",
                                          "kind": "Int",
                                        },
                                      },
                                      "bit_width": { "None": true },
                                    },
                                    {
                                      "type": "StructField",
                                      "name": "y",
                                      "ctype": {
                                        "type": "CType",
                                        "repr": "int",
                                        "qualifiers": {
                                          "const": false,
                                          "volatile": false,
                                          "restrict": false,
                                          "atomic": false,
                                        },
                                        "dataKind": {
                                          "type": "CTypeDataKind",
                                          "kind": "Int",
                                        },
                                      },
                                      "bit_width": { "None": true },
                                    },
                                  ],
                                },
                              },
                              "bit_width": { "None": true },
                            },
                          ],
                        },
                      },
                      "name": "w",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "struct Wrap *",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Ptr",
                          "to": {
                            "type": "CType",
                            "repr": "struct Wrap",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Struct",
                              "name": "Wrap",
                              "fields": [
                                {
                                  "type": "StructField",
                                  "name": "p",
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "struct Point",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Struct",
                                      "name": "Point",
                                      "fields": [
                                        {
                                          "type": "StructField",
                                          "name": "x",
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "int",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Int",
                                            },
                                          },
                                          "bit_width": { "None": true },
                                        },
                                        {
                                          "type": "StructField",
                                          "name": "y",
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "int",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Int",
                                            },
                                          },
                                          "bit_width": { "None": true },
                                        },
                                      ],
                                    },
                                  },
                                  "bit_width": { "None": true },
                                },
                              ],
                            },
                          },
                        },
                      },
                      "name": "q",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "UnaryExpr",
                              "kind": {
                                "type": "UnaryExprKind",
                                "kind": "AddrOf",
                                "expr": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "w",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "struct Wrap",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Struct",
                                      "name": "Wrap",
                                      "fields": [
                                        {
                                          "type": "StructField",
                                          "name": "p",
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "struct Point",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Struct",
                                              "name": "Point",
                                              "fields": [
                                                {
                                                  "type": "StructField",
                                                  "name": "x",
                                                  "ctype": {
                                                    "type": "CType",
                                                    "repr": "int",
                                                    "qualifiers": {
                                                      "const": false,
                                                      "volatile": false,
                                                      "restrict": false,
                                                      "atomic": false,
                                                    },
                                                    "dataKind": {
                                                      "type": "CTypeDataKind",
                                                      "kind": "Int",
                                                    },
                                                  },
                                                  "bit_width": { "None": true },
                                                },
                                                {
                                                  "type": "StructField",
                                                  "name": "y",
                                                  "ctype": {
                                                    "type": "CType",
                                                    "repr": "int",
                                                    "qualifiers": {
                                                      "const": false,
                                                      "volatile": false,
                                                      "restrict": false,
                                                      "atomic": false,
                                                    },
                                                    "dataKind": {
                                                      "type": "CTypeDataKind",
                                                      "kind": "Int",
                                                    },
                                                  },
                                                  "bit_width": { "None": true },
                                                },
                                              ],
                                            },
                                          },
                                          "bit_width": { "None": true },
                                        },
                                      ],
                                    },
                                  },
                                },
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "struct Wrap *",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Ptr",
                                  "to": {
                                    "type": "CType",
                                    "repr": "struct Wrap",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Struct",
                                      "name": "Wrap",
                                      "fields": [
                                        {
                                          "type": "StructField",
                                          "name": "p",
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "struct Point",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Struct",
                                              "name": "Point",
                                              "fields": [
                                                {
                                                  "type": "StructField",
                                                  "name": "x",
                                                  "ctype": {
                                                    "type": "CType",
                                                    "repr": "int",
                                                    "qualifiers": {
                                                      "const": false,
                                                      "volatile": false,
                                                      "restrict": false,
                                                      "atomic": false,
                                                    },
                                                    "dataKind": {
                                                      "type": "CTypeDataKind",
                                                      "kind": "Int",
                                                    },
                                                  },
                                                  "bit_width": { "None": true },
                                                },
                                                {
                                                  "type": "StructField",
                                                  "name": "y",
                                                  "ctype": {
                                                    "type": "CType",
                                                    "repr": "int",
                                                    "qualifiers": {
                                                      "const": false,
                                                      "volatile": false,
                                                      "restrict": false,
                                                      "atomic": false,
                                                    },
                                                    "dataKind": {
                                                      "type": "CTypeDataKind",
                                                      "kind": "Int",
                                                    },
                                                  },
                                                  "bit_width": { "None": true },
                                                },
                                              ],
                                            },
                                          },
                                          "bit_width": { "None": true },
                                        },
                                      ],
                                    },
                                  },
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "MemberAccess",
                              "object": {
                                "type": "PostfixExpr",
                                "kind": {
                                  "type": "PostfixExprKind",
                                  "kind": "PtrMemberAccess",
                                  "object": {
                                    "type": "PrimExpr",
                                    "kind": {
                                      "type": "PrimExprKind",
                                      "kind": "Ident",
                                      "name": "q",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "struct Wrap *",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Ptr",
                                        "to": {
                                          "type": "CType",
                                          "repr": "struct Wrap",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Struct",
                                            "name": "Wrap",
                                            "fields": [
                                              {
                                                "type": "StructField",
                                                "name": "p",
                                                "ctype": {
                                                  "type": "CType",
                                                  "repr": "struct Point",
                                                  "qualifiers": {
                                                    "const": false,
                                                    "volatile": false,
                                                    "restrict": false,
                                                    "atomic": false,
                                                  },
                                                  "dataKind": {
                                                    "type": "CTypeDataKind",
                                                    "kind": "Struct",
                                                    "name": "Point",
                                                    "fields": [
                                                      {
                                                        "type": "StructField",
                                                        "name": "x",
                                                        "ctype": {
                                                          "type": "CType",
                                                          "repr": "int",
                                                          "qualifiers": {
                                                            "const": false,
                                                            "volatile": false,
                                                            "restrict": false,
                                                            "atomic": false,
                                                          },
                                                          "dataKind": {
                                                            "type": "CTypeDataKind",
                                                            "kind": "Int",
                                                          },
                                                        },
                                                        "bit_width": {
                                                          "None": true,
                                                        },
                                                      },
                                                      {
                                                        "type": "StructField",
                                                        "name": "y",
                                                        "ctype": {
                                                          "type": "CType",
                                                          "repr": "int",
                                                          "qualifiers": {
                                                            "const": false,
                                                            "volatile": false,
                                                            "restrict": false,
                                                            "atomic": false,
                                                          },
                                                          "dataKind": {
                                                            "type": "CTypeDataKind",
                                                            "kind": "Int",
                                                          },
                                                        },
                                                        "bit_width": {
                                                          "None": true,
                                                        },
                                                      },
                                                    ],
                                                  },
                                                },
                                                "bit_width": { "None": true },
                                              },
                                            ],
                                          },
                                        },
                                      },
                                    },
                                  },
                                  "field": "p",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "struct Point",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Struct",
                                    "name": "Point",
                                    "fields": [
                                      {
                                        "type": "StructField",
                                        "name": "x",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                      {
                                        "type": "StructField",
                                        "name": "y",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                    ],
                                  },
                                },
                              },
                              "field": "x",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "MemberAccess",
                          "object": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "PtrMemberAccess",
                              "object": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "q",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "struct Wrap *",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Ptr",
                                    "to": {
                                      "type": "CType",
                                      "repr": "struct Wrap",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Struct",
                                        "name": "Wrap",
                                        "fields": [
                                          {
                                            "type": "StructField",
                                            "name": "p",
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "struct Point",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Struct",
                                                "name": "Point",
                                                "fields": [
                                                  {
                                                    "type": "StructField",
                                                    "name": "x",
                                                    "ctype": {
                                                      "type": "CType",
                                                      "repr": "int",
                                                      "qualifiers": {
                                                        "const": false,
                                                        "volatile": false,
                                                        "restrict": false,
                                                        "atomic": false,
                                                      },
                                                      "dataKind": {
                                                        "type": "CTypeDataKind",
                                                        "kind": "Int",
                                                      },
                                                    },
                                                    "bit_width": {
                                                      "None": true,
                                                    },
                                                  },
                                                  {
                                                    "type": "StructField",
                                                    "name": "y",
                                                    "ctype": {
                                                      "type": "CType",
                                                      "repr": "int",
                                                      "qualifiers": {
                                                        "const": false,
                                                        "volatile": false,
                                                        "restrict": false,
                                                        "atomic": false,
                                                      },
                                                      "dataKind": {
                                                        "type": "CTypeDataKind",
                                                        "kind": "Int",
                                                      },
                                                    },
                                                    "bit_width": {
                                                      "None": true,
                                                    },
                                                  },
                                                ],
                                              },
                                            },
                                            "bit_width": { "None": true },
                                          },
                                        ],
                                      },
                                    },
                                  },
                                },
                              },
                              "field": "p",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "struct Point",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Struct",
                                "name": "Point",
                                "fields": [
                                  {
                                    "type": "StructField",
                                    "name": "x",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "bit_width": { "None": true },
                                  },
                                  {
                                    "type": "StructField",
                                    "name": "y",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "bit_width": { "None": true },
                                  },
                                ],
                              },
                            },
                          },
                          "field": "x",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "assign expr/mul assign *=" {
  let code =
    #|int foo() { int a = 6; a *= 7; return a; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "a",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "6",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "a",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "*=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "7",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "a",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "assign expr/div assign /=" {
  let code =
    #|int foo() { int a = 8; a /= 2; return a; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "a",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "8",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "a",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "/=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "2",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "a",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "assign expr/mod assign %=" {
  let code =
    #|int foo() { int a = 9; a %= 4; return a; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "a",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "9",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "a",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "%=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "4",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "a",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "assign expr/shr assign >>=" {
  let code =
    #|int foo() { int a = 8; a >>= 1; return a; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "a",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "8",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "a",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": ">>=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "a",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "assign expr/and assign &=" {
  let code =
    #|int foo() { int a = 6; a &= 3; return a; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "a",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "6",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "a",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "&=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "3",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "a",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "assign expr/xor assign ^=" {
  let code =
    #|int foo() { int a = 6; a ^= 3; return a; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "a",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "6",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "a",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "^=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "3",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "a",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "assign expr/or assign |=" {
  let code =
    #|int foo() { int a = 6; a |= 3; return a; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "a",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "6",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "a",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "|=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "3",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "a",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "stmt/for expr init" {
  let code =
    #|int foo() { int i = 0; int s = 0; for (i = 0; i < 3; i++) { s += i; } return s; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "s",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "For",
                      "stmt": {
                        "type": "ForStmt",
                        "init": {
                          "Some": {
                            "type": "ForInit",
                            "kind": "Expr",
                            "expr": {
                              "type": "AssignExpr",
                              "kind": {
                                "type": "AssignExprKind",
                                "kind": "Assign",
                                "lhs": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "i",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                },
                                "op": { "type": "AssignOp", "op": "=" },
                                "rhs": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Int",
                                    "value": "0",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                },
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                        "cond": {
                          "Some": {
                            "type": "RelationalExpr",
                            "kind": {
                              "type": "RelationalExprKind",
                              "kind": "LTExpr",
                              "lhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "i",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                              "rhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Int",
                                  "value": "3",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "update": {
                          "Some": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "PostInc",
                              "expr": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "i",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "body": {
                          "type": "Statement",
                          "kind": {
                            "type": "StmtKind",
                            "kind": "Compound",
                            "body": {
                              "type": "CompoundStmt",
                              "items": [
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Expr",
                                      "expr": {
                                        "type": "AssignExpr",
                                        "kind": {
                                          "type": "AssignExprKind",
                                          "kind": "Assign",
                                          "lhs": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "s",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                          "op": {
                                            "type": "AssignOp",
                                            "op": "+=",
                                          },
                                          "rhs": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "i",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              ],
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "s",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "stmt/for no init" {
  let code =
    #|int foo() { int i = 0; int s = 0; for (; i < 3; i++) { s += i; } return s; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "s",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "For",
                      "stmt": {
                        "type": "ForStmt",
                        "init": { "None": true },
                        "cond": {
                          "Some": {
                            "type": "RelationalExpr",
                            "kind": {
                              "type": "RelationalExprKind",
                              "kind": "LTExpr",
                              "lhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "i",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                              "rhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Int",
                                  "value": "3",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "update": {
                          "Some": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "PostInc",
                              "expr": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "i",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "body": {
                          "type": "Statement",
                          "kind": {
                            "type": "StmtKind",
                            "kind": "Compound",
                            "body": {
                              "type": "CompoundStmt",
                              "items": [
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Expr",
                                      "expr": {
                                        "type": "AssignExpr",
                                        "kind": {
                                          "type": "AssignExprKind",
                                          "kind": "Assign",
                                          "lhs": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "s",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                          "op": {
                                            "type": "AssignOp",
                                            "op": "+=",
                                          },
                                          "rhs": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "i",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              ],
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "s",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "stmt/for no update" {
  let code =
    #|int foo() { int i = 0; int s = 0; for (i = 0; i < 3; ) { s += i; i++; } return s; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "s",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "For",
                      "stmt": {
                        "type": "ForStmt",
                        "init": {
                          "Some": {
                            "type": "ForInit",
                            "kind": "Expr",
                            "expr": {
                              "type": "AssignExpr",
                              "kind": {
                                "type": "AssignExprKind",
                                "kind": "Assign",
                                "lhs": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "i",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                },
                                "op": { "type": "AssignOp", "op": "=" },
                                "rhs": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Int",
                                    "value": "0",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int",
                                    "qualifiers": {
                                      "const": false,
                                      "volatile": false,
                                      "restrict": false,
                                      "atomic": false,
                                    },
                                    "dataKind": {
                                      "type": "CTypeDataKind",
                                      "kind": "Int",
                                    },
                                  },
                                },
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                        "cond": {
                          "Some": {
                            "type": "RelationalExpr",
                            "kind": {
                              "type": "RelationalExprKind",
                              "kind": "LTExpr",
                              "lhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "i",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                              "rhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Int",
                                  "value": "3",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                              },
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "update": { "None": true },
                        "body": {
                          "type": "Statement",
                          "kind": {
                            "type": "StmtKind",
                            "kind": "Compound",
                            "body": {
                              "type": "CompoundStmt",
                              "items": [
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Expr",
                                      "expr": {
                                        "type": "AssignExpr",
                                        "kind": {
                                          "type": "AssignExprKind",
                                          "kind": "Assign",
                                          "lhs": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "s",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                          "op": {
                                            "type": "AssignOp",
                                            "op": "+=",
                                          },
                                          "rhs": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "i",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Expr",
                                      "expr": {
                                        "type": "PostfixExpr",
                                        "kind": {
                                          "type": "PostfixExprKind",
                                          "kind": "PostInc",
                                          "expr": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "i",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              ],
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "s",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "stmt/for infinite with break" {
  let code =
    #|int foo() { int i = 0; for (;;) { if (i == 3) break; i++; } return i; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "i",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "For",
                      "stmt": {
                        "type": "ForStmt",
                        "init": { "None": true },
                        "cond": { "None": true },
                        "update": { "None": true },
                        "body": {
                          "type": "Statement",
                          "kind": {
                            "type": "StmtKind",
                            "kind": "Compound",
                            "body": {
                              "type": "CompoundStmt",
                              "items": [
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "If",
                                      "stmt": {
                                        "type": "IfStmt",
                                        "cond": {
                                          "type": "EqualityExpr",
                                          "kind": {
                                            "type": "EqualityExprKind",
                                            "kind": "EQExpr",
                                            "lhs": {
                                              "type": "PrimExpr",
                                              "kind": {
                                                "type": "PrimExprKind",
                                                "kind": "Ident",
                                                "name": "i",
                                              },
                                              "ctype": {
                                                "type": "CType",
                                                "repr": "int",
                                                "qualifiers": {
                                                  "const": false,
                                                  "volatile": false,
                                                  "restrict": false,
                                                  "atomic": false,
                                                },
                                                "dataKind": {
                                                  "type": "CTypeDataKind",
                                                  "kind": "Int",
                                                },
                                              },
                                            },
                                            "rhs": {
                                              "type": "PrimExpr",
                                              "kind": {
                                                "type": "PrimExprKind",
                                                "kind": "Int",
                                                "value": "3",
                                              },
                                              "ctype": {
                                                "type": "CType",
                                                "repr": "int",
                                                "qualifiers": {
                                                  "const": false,
                                                  "volatile": false,
                                                  "restrict": false,
                                                  "atomic": false,
                                                },
                                                "dataKind": {
                                                  "type": "CTypeDataKind",
                                                  "kind": "Int",
                                                },
                                              },
                                            },
                                          },
                                          "ctype": {
                                            "type": "CType",
                                            "repr": "int",
                                            "qualifiers": {
                                              "const": false,
                                              "volatile": false,
                                              "restrict": false,
                                              "atomic": false,
                                            },
                                            "dataKind": {
                                              "type": "CTypeDataKind",
                                              "kind": "Int",
                                            },
                                          },
                                        },
                                        "then": {
                                          "type": "Statement",
                                          "kind": {
                                            "type": "StmtKind",
                                            "kind": "Break",
                                          },
                                        },
                                        "else": { "None": true },
                                      },
                                    },
                                  },
                                },
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Expr",
                                      "expr": {
                                        "type": "PostfixExpr",
                                        "kind": {
                                          "type": "PostfixExprKind",
                                          "kind": "PostInc",
                                          "expr": {
                                            "type": "PrimExpr",
                                            "kind": {
                                              "type": "PrimExprKind",
                                              "kind": "Ident",
                                              "name": "i",
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              ],
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "i",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "stmt/switch fallthrough and break" {
  let code =
    #|int foo(int x) {
    #|  int r = 0;
    #|  switch (x) {
    #|    case 0: r = 1;
    #|    case 1: r = r + 2; break;
    #|    default: r = 9;
    #|  }
    #|  return r;
    #|}
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "x",
              },
            ],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "r",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Switch",
                      "stmt": {
                        "type": "SwitchStmt",
                        "expr": {
                          "type": "PrimExpr",
                          "kind": {
                            "type": "PrimExprKind",
                            "kind": "Ident",
                            "name": "x",
                          },
                          "ctype": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                        },
                        "body": {
                          "type": "Statement",
                          "kind": {
                            "type": "StmtKind",
                            "kind": "Compound",
                            "body": {
                              "type": "CompoundStmt",
                              "items": [
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Case",
                                      "expr": {
                                        "type": "PrimExpr",
                                        "kind": {
                                          "type": "PrimExprKind",
                                          "kind": "Int",
                                          "value": "0",
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                      "stmt": {
                                        "type": "Statement",
                                        "kind": {
                                          "type": "StmtKind",
                                          "kind": "Expr",
                                          "expr": {
                                            "type": "AssignExpr",
                                            "kind": {
                                              "type": "AssignExprKind",
                                              "kind": "Assign",
                                              "lhs": {
                                                "type": "PrimExpr",
                                                "kind": {
                                                  "type": "PrimExprKind",
                                                  "kind": "Ident",
                                                  "name": "r",
                                                },
                                                "ctype": {
                                                  "type": "CType",
                                                  "repr": "int",
                                                  "qualifiers": {
                                                    "const": false,
                                                    "volatile": false,
                                                    "restrict": false,
                                                    "atomic": false,
                                                  },
                                                  "dataKind": {
                                                    "type": "CTypeDataKind",
                                                    "kind": "Int",
                                                  },
                                                },
                                              },
                                              "op": {
                                                "type": "AssignOp",
                                                "op": "=",
                                              },
                                              "rhs": {
                                                "type": "PrimExpr",
                                                "kind": {
                                                  "type": "PrimExprKind",
                                                  "kind": "Int",
                                                  "value": "1",
                                                },
                                                "ctype": {
                                                  "type": "CType",
                                                  "repr": "int",
                                                  "qualifiers": {
                                                    "const": false,
                                                    "volatile": false,
                                                    "restrict": false,
                                                    "atomic": false,
                                                  },
                                                  "dataKind": {
                                                    "type": "CTypeDataKind",
                                                    "kind": "Int",
                                                  },
                                                },
                                              },
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Case",
                                      "expr": {
                                        "type": "PrimExpr",
                                        "kind": {
                                          "type": "PrimExprKind",
                                          "kind": "Int",
                                          "value": "1",
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                      "stmt": {
                                        "type": "Statement",
                                        "kind": {
                                          "type": "StmtKind",
                                          "kind": "Expr",
                                          "expr": {
                                            "type": "AssignExpr",
                                            "kind": {
                                              "type": "AssignExprKind",
                                              "kind": "Assign",
                                              "lhs": {
                                                "type": "PrimExpr",
                                                "kind": {
                                                  "type": "PrimExprKind",
                                                  "kind": "Ident",
                                                  "name": "r",
                                                },
                                                "ctype": {
                                                  "type": "CType",
                                                  "repr": "int",
                                                  "qualifiers": {
                                                    "const": false,
                                                    "volatile": false,
                                                    "restrict": false,
                                                    "atomic": false,
                                                  },
                                                  "dataKind": {
                                                    "type": "CTypeDataKind",
                                                    "kind": "Int",
                                                  },
                                                },
                                              },
                                              "op": {
                                                "type": "AssignOp",
                                                "op": "=",
                                              },
                                              "rhs": {
                                                "type": "AddiExpr",
                                                "kind": {
                                                  "type": "AddiExprKind",
                                                  "kind": "AddExpr",
                                                  "lhs": {
                                                    "type": "PrimExpr",
                                                    "kind": {
                                                      "type": "PrimExprKind",
                                                      "kind": "Ident",
                                                      "name": "r",
                                                    },
                                                    "ctype": {
                                                      "type": "CType",
                                                      "repr": "int",
                                                      "qualifiers": {
                                                        "const": false,
                                                        "volatile": false,
                                                        "restrict": false,
                                                        "atomic": false,
                                                      },
                                                      "dataKind": {
                                                        "type": "CTypeDataKind",
                                                        "kind": "Int",
                                                      },
                                                    },
                                                  },
                                                  "rhs": {
                                                    "type": "PrimExpr",
                                                    "kind": {
                                                      "type": "PrimExprKind",
                                                      "kind": "Int",
                                                      "value": "2",
                                                    },
                                                    "ctype": {
                                                      "type": "CType",
                                                      "repr": "int",
                                                      "qualifiers": {
                                                        "const": false,
                                                        "volatile": false,
                                                        "restrict": false,
                                                        "atomic": false,
                                                      },
                                                      "dataKind": {
                                                        "type": "CTypeDataKind",
                                                        "kind": "Int",
                                                      },
                                                    },
                                                  },
                                                },
                                                "ctype": {
                                                  "type": "CType",
                                                  "repr": "int",
                                                  "qualifiers": {
                                                    "const": false,
                                                    "volatile": false,
                                                    "restrict": false,
                                                    "atomic": false,
                                                  },
                                                  "dataKind": {
                                                    "type": "CTypeDataKind",
                                                    "kind": "Int",
                                                  },
                                                },
                                              },
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Break",
                                    },
                                  },
                                },
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "DefaultCase",
                                      "stmt": {
                                        "type": "Statement",
                                        "kind": {
                                          "type": "StmtKind",
                                          "kind": "Expr",
                                          "expr": {
                                            "type": "AssignExpr",
                                            "kind": {
                                              "type": "AssignExprKind",
                                              "kind": "Assign",
                                              "lhs": {
                                                "type": "PrimExpr",
                                                "kind": {
                                                  "type": "PrimExprKind",
                                                  "kind": "Ident",
                                                  "name": "r",
                                                },
                                                "ctype": {
                                                  "type": "CType",
                                                  "repr": "int",
                                                  "qualifiers": {
                                                    "const": false,
                                                    "volatile": false,
                                                    "restrict": false,
                                                    "atomic": false,
                                                  },
                                                  "dataKind": {
                                                    "type": "CTypeDataKind",
                                                    "kind": "Int",
                                                  },
                                                },
                                              },
                                              "op": {
                                                "type": "AssignOp",
                                                "op": "=",
                                              },
                                              "rhs": {
                                                "type": "PrimExpr",
                                                "kind": {
                                                  "type": "PrimExprKind",
                                                  "kind": "Int",
                                                  "value": "9",
                                                },
                                                "ctype": {
                                                  "type": "CType",
                                                  "repr": "int",
                                                  "qualifiers": {
                                                    "const": false,
                                                    "volatile": false,
                                                    "restrict": false,
                                                    "atomic": false,
                                                  },
                                                  "dataKind": {
                                                    "type": "CTypeDataKind",
                                                    "kind": "Int",
                                                  },
                                                },
                                              },
                                            },
                                            "ctype": {
                                              "type": "CType",
                                              "repr": "int",
                                              "qualifiers": {
                                                "const": false,
                                                "volatile": false,
                                                "restrict": false,
                                                "atomic": false,
                                              },
                                              "dataKind": {
                                                "type": "CTypeDataKind",
                                                "kind": "Int",
                                              },
                                            },
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              ],
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "r",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "stmt/switch case block" {
  let code =
    #|int foo(int x) {
    #|  switch (x) {
    #|    case 0: { int a = 1; return a; }
    #|    default: { int b = 2; return b; }
    #|  }
    #|}
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [
              {
                "type": "Param",
                "ctype": {
                  "type": "CType",
                  "repr": "int",
                  "qualifiers": {
                    "const": false,
                    "volatile": false,
                    "restrict": false,
                    "atomic": false,
                  },
                  "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                },
                "name": "x",
              },
            ],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Switch",
                      "stmt": {
                        "type": "SwitchStmt",
                        "expr": {
                          "type": "PrimExpr",
                          "kind": {
                            "type": "PrimExprKind",
                            "kind": "Ident",
                            "name": "x",
                          },
                          "ctype": {
                            "type": "CType",
                            "repr": "int",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int",
                            },
                          },
                        },
                        "body": {
                          "type": "Statement",
                          "kind": {
                            "type": "StmtKind",
                            "kind": "Compound",
                            "body": {
                              "type": "CompoundStmt",
                              "items": [
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "Case",
                                      "expr": {
                                        "type": "PrimExpr",
                                        "kind": {
                                          "type": "PrimExprKind",
                                          "kind": "Int",
                                          "value": "0",
                                        },
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                      },
                                      "stmt": {
                                        "type": "Statement",
                                        "kind": {
                                          "type": "StmtKind",
                                          "kind": "Compound",
                                          "body": {
                                            "type": "CompoundStmt",
                                            "items": [
                                              {
                                                "Right": {
                                                  "type": "Declaration",
                                                  "kind": {
                                                    "type": "DeclarationKind",
                                                    "kind": "VariableDeclaration",
                                                    "ctype": {
                                                      "type": "CType",
                                                      "repr": "int",
                                                      "qualifiers": {
                                                        "const": false,
                                                        "volatile": false,
                                                        "restrict": false,
                                                        "atomic": false,
                                                      },
                                                      "dataKind": {
                                                        "type": "CTypeDataKind",
                                                        "kind": "Int",
                                                      },
                                                    },
                                                    "name": "a",
                                                    "storage": {
                                                      "static": false,
                                                      "extern": false,
                                                      "register": false,
                                                      "thread_local": false,
                                                    },
                                                    "init": {
                                                      "Some": {
                                                        "type": "Initializer",
                                                        "kind": {
                                                          "type": "InitializerKind",
                                                          "kind": "AssignExpr",
                                                          "expr": {
                                                            "type": "PrimExpr",
                                                            "kind": {
                                                              "type": "PrimExprKind",
                                                              "kind": "Int",
                                                              "value": "1",
                                                            },
                                                            "ctype": {
                                                              "type": "CType",
                                                              "repr": "int",
                                                              "qualifiers": {
                                                                "const": false,
                                                                "volatile": false,
                                                                "restrict": false,
                                                                "atomic": false,
                                                              },
                                                              "dataKind": {
                                                                "type": "CTypeDataKind",
                                                                "kind": "Int",
                                                              },
                                                            },
                                                          },
                                                        },
                                                      },
                                                    },
                                                  },
                                                },
                                              },
                                              {
                                                "Left": {
                                                  "type": "Statement",
                                                  "kind": {
                                                    "type": "StmtKind",
                                                    "kind": "Return",
                                                    "expr": {
                                                      "type": "PrimExpr",
                                                      "kind": {
                                                        "type": "PrimExprKind",
                                                        "kind": "Ident",
                                                        "name": "a",
                                                      },
                                                      "ctype": {
                                                        "type": "CType",
                                                        "repr": "int",
                                                        "qualifiers": {
                                                          "const": false,
                                                          "volatile": false,
                                                          "restrict": false,
                                                          "atomic": false,
                                                        },
                                                        "dataKind": {
                                                          "type": "CTypeDataKind",
                                                          "kind": "Int",
                                                        },
                                                      },
                                                    },
                                                  },
                                                },
                                              },
                                            ],
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                                {
                                  "Left": {
                                    "type": "Statement",
                                    "kind": {
                                      "type": "StmtKind",
                                      "kind": "DefaultCase",
                                      "stmt": {
                                        "type": "Statement",
                                        "kind": {
                                          "type": "StmtKind",
                                          "kind": "Compound",
                                          "body": {
                                            "type": "CompoundStmt",
                                            "items": [
                                              {
                                                "Right": {
                                                  "type": "Declaration",
                                                  "kind": {
                                                    "type": "DeclarationKind",
                                                    "kind": "VariableDeclaration",
                                                    "ctype": {
                                                      "type": "CType",
                                                      "repr": "int",
                                                      "qualifiers": {
                                                        "const": false,
                                                        "volatile": false,
                                                        "restrict": false,
                                                        "atomic": false,
                                                      },
                                                      "dataKind": {
                                                        "type": "CTypeDataKind",
                                                        "kind": "Int",
                                                      },
                                                    },
                                                    "name": "b",
                                                    "storage": {
                                                      "static": false,
                                                      "extern": false,
                                                      "register": false,
                                                      "thread_local": false,
                                                    },
                                                    "init": {
                                                      "Some": {
                                                        "type": "Initializer",
                                                        "kind": {
                                                          "type": "InitializerKind",
                                                          "kind": "AssignExpr",
                                                          "expr": {
                                                            "type": "PrimExpr",
                                                            "kind": {
                                                              "type": "PrimExprKind",
                                                              "kind": "Int",
                                                              "value": "2",
                                                            },
                                                            "ctype": {
                                                              "type": "CType",
                                                              "repr": "int",
                                                              "qualifiers": {
                                                                "const": false,
                                                                "volatile": false,
                                                                "restrict": false,
                                                                "atomic": false,
                                                              },
                                                              "dataKind": {
                                                                "type": "CTypeDataKind",
                                                                "kind": "Int",
                                                              },
                                                            },
                                                          },
                                                        },
                                                      },
                                                    },
                                                  },
                                                },
                                              },
                                              {
                                                "Left": {
                                                  "type": "Statement",
                                                  "kind": {
                                                    "type": "StmtKind",
                                                    "kind": "Return",
                                                    "expr": {
                                                      "type": "PrimExpr",
                                                      "kind": {
                                                        "type": "PrimExprKind",
                                                        "kind": "Ident",
                                                        "name": "b",
                                                      },
                                                      "ctype": {
                                                        "type": "CType",
                                                        "repr": "int",
                                                        "qualifiers": {
                                                          "const": false,
                                                          "volatile": false,
                                                          "restrict": false,
                                                          "atomic": false,
                                                        },
                                                        "dataKind": {
                                                          "type": "CTypeDataKind",
                                                          "kind": "Int",
                                                        },
                                                      },
                                                    },
                                                  },
                                                },
                                              },
                                            ],
                                          },
                                        },
                                      },
                                    },
                                  },
                                },
                              ],
                            },
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "keyword/short" {
  let code =
    #|int foo() { short s = 7; return s; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "short",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int16" },
                      },
                      "name": "s",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "7",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "s",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "short",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "Int16",
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "keyword/_Bool" {
  let code =
    #|int foo() { _Bool b = 1; return b; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "b",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "b",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "keyword/typedef basic" {
  let code =
    #|typedef int MyInt;
    #|MyInt foo() { MyInt x = 1; return x; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "TypeDef",
              "ctype": {
                "type": "CType",
                "repr": "int",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
              },
              "name": "MyInt",
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "x",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "x",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "keyword/static global variable" {
  let code =
    #|static int g = 3;
    #|int foo() { return g; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "VariableDeclaration",
              "ctype": {
                "type": "CType",
                "repr": "int",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
              },
              "name": "g",
              "storage": {
                "static": true,
                "extern": false,
                "register": false,
                "thread_local": false,
              },
              "init": {
                "Some": {
                  "type": "Initializer",
                  "kind": {
                    "type": "InitializerKind",
                    "kind": "AssignExpr",
                    "expr": {
                      "type": "PrimExpr",
                      "kind": {
                        "type": "PrimExprKind",
                        "kind": "Int",
                        "value": "3",
                      },
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "g",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "keyword/static function" {
  let code =
    #|static int bar() { return 1; }
    #|int foo() { return bar(); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "bar",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": true,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Int",
                          "value": "1",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "FuncCall",
                          "callee": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "bar",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int ()",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Function",
                                "params": [],
                                "ret": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Int",
                                  },
                                },
                                "variadic": false,
                              },
                            },
                          },
                          "args": [],
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "keyword/const local" {
  let code =
    #|int foo() { const int x = 1; return x; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "const int",
                        "qualifiers": {
                          "const": true,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "x",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "x",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "const int",
                          "qualifiers": {
                            "const": true,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "keyword/volatile local" {
  let code =
    #|int foo() { volatile int x = 1; return x; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "volatile int",
                        "qualifiers": {
                          "const": false,
                          "volatile": true,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "x",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "x",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "volatile int",
                          "qualifiers": {
                            "const": false,
                            "volatile": true,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "keyword/sizeof type short" {
  let code =
    #|long foo() { return sizeof(short); }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "long",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Long" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "SizeofType",
                          "ctype": {
                            "type": "CType",
                            "repr": "short",
                            "qualifiers": {
                              "const": false,
                              "volatile": false,
                              "restrict": false,
                              "atomic": false,
                            },
                            "dataKind": {
                              "type": "CTypeDataKind",
                              "kind": "Int16",
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "unsigned long",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "ULong",
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "keyword/sizeof expr" {
  let code =
    #|long foo() { int x = 0; return sizeof x; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "long",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Long" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "name": "x",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "0",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "UnaryExpr",
                        "kind": {
                          "type": "UnaryExprKind",
                          "kind": "SizeofExpr",
                          "expr": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "x",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "unsigned long",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "ULong",
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "keyword/union basic" {
  let code =
    #|union U { int x; char c; };
    #|int foo() { union U u; u.x = 1; return u.x; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "TypeDeclaration",
              "ctype": {
                "type": "CType",
                "repr": "union U",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": {
                  "type": "CTypeDataKind",
                  "kind": "Union",
                  "name": "U",
                  "fields": [
                    {
                      "type": "StructField",
                      "name": "x",
                      "ctype": {
                        "type": "CType",
                        "repr": "int",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                      },
                      "bit_width": { "None": true },
                    },
                    {
                      "type": "StructField",
                      "name": "c",
                      "ctype": {
                        "type": "CType",
                        "repr": "char",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": { "type": "CTypeDataKind", "kind": "Char" },
                      },
                      "bit_width": { "None": true },
                    },
                  ],
                },
              },
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "union U",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Union",
                          "name": "U",
                          "fields": [
                            {
                              "type": "StructField",
                              "name": "x",
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                              "bit_width": { "None": true },
                            },
                            {
                              "type": "StructField",
                              "name": "c",
                              "ctype": {
                                "type": "CType",
                                "repr": "char",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Char",
                                },
                              },
                              "bit_width": { "None": true },
                            },
                          ],
                        },
                      },
                      "name": "u",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": { "None": true },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Expr",
                      "expr": {
                        "type": "AssignExpr",
                        "kind": {
                          "type": "AssignExprKind",
                          "kind": "Assign",
                          "lhs": {
                            "type": "PostfixExpr",
                            "kind": {
                              "type": "PostfixExprKind",
                              "kind": "MemberAccess",
                              "object": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "u",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "union U",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
                                    "restrict": false,
                                    "atomic": false,
                                  },
                                  "dataKind": {
                                    "type": "CTypeDataKind",
                                    "kind": "Union",
                                    "name": "U",
                                    "fields": [
                                      {
                                        "type": "StructField",
                                        "name": "x",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "int",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Int",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                      {
                                        "type": "StructField",
                                        "name": "c",
                                        "ctype": {
                                          "type": "CType",
                                          "repr": "char",
                                          "qualifiers": {
                                            "const": false,
                                            "volatile": false,
                                            "restrict": false,
                                            "atomic": false,
                                          },
                                          "dataKind": {
                                            "type": "CTypeDataKind",
                                            "kind": "Char",
                                          },
                                        },
                                        "bit_width": { "None": true },
                                      },
                                    ],
                                  },
                                },
                              },
                              "field": "x",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                          "op": { "type": "AssignOp", "op": "=" },
                          "rhs": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Int",
                              "value": "1",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "int",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Int",
                              },
                            },
                          },
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PostfixExpr",
                        "kind": {
                          "type": "PostfixExprKind",
                          "kind": "MemberAccess",
                          "object": {
                            "type": "PrimExpr",
                            "kind": {
                              "type": "PrimExprKind",
                              "kind": "Ident",
                              "name": "u",
                            },
                            "ctype": {
                              "type": "CType",
                              "repr": "union U",
                              "qualifiers": {
                                "const": false,
                                "volatile": false,
                                "restrict": false,
                                "atomic": false,
                              },
                              "dataKind": {
                                "type": "CTypeDataKind",
                                "kind": "Union",
                                "name": "U",
                                "fields": [
                                  {
                                    "type": "StructField",
                                    "name": "x",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Int",
                                      },
                                    },
                                    "bit_width": { "None": true },
                                  },
                                  {
                                    "type": "StructField",
                                    "name": "c",
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "char",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
                                        "restrict": false,
                                        "atomic": false,
                                      },
                                      "dataKind": {
                                        "type": "CTypeDataKind",
                                        "kind": "Char",
                                      },
                                    },
                                    "bit_width": { "None": true },
                                  },
                                ],
                              },
                            },
                          },
                          "field": "x",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "keyword/enum basic" {
  let code =
    #|enum E { A = 1, B = 2 };
    #|int foo() { enum E e = A; return e; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "TypeDeclaration",
              "ctype": {
                "type": "CType",
                "repr": "enum E",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": {
                  "type": "CTypeDataKind",
                  "kind": "Enum",
                  "name": "E",
                  "members": [
                    { "name": "A", "value": "1" },
                    { "name": "B", "value": "2" },
                  ],
                },
              },
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "enum E",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Enum",
                          "name": "E",
                          "members": [],
                        },
                      },
                      "name": "e",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "e",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "enum E",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "Enum",
                            "name": "E",
                            "members": [],
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}

///|
test "keyword/enum forward + typedef" {
  let code =
    #|enum E { A = 1 };
    #|typedef enum E E;
    #|int foo() { E e = A; return e; }
  let c_ast = parse(code)
  json_inspect(c_ast.to_test_json(), content={
    "type": "Program",
    "externals": [
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "TypeDeclaration",
              "ctype": {
                "type": "CType",
                "repr": "enum E",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": {
                  "type": "CTypeDataKind",
                  "kind": "Enum",
                  "name": "E",
                  "members": [{ "name": "A", "value": "1" }],
                },
              },
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "Declaration",
          "value": {
            "type": "Declaration",
            "kind": {
              "type": "DeclarationKind",
              "kind": "TypeDef",
              "ctype": {
                "type": "CType",
                "repr": "enum E",
                "qualifiers": {
                  "const": false,
                  "volatile": false,
                  "restrict": false,
                  "atomic": false,
                },
                "dataKind": {
                  "type": "CTypeDataKind",
                  "kind": "Enum",
                  "name": "E",
                  "members": [],
                },
              },
              "name": "E",
            },
          },
        },
      },
      {
        "type": "ExternalDeclaration",
        "kind": {
          "type": "ExternalDeclarationKind",
          "kind": "FunctionDefinition",
          "value": {
            "type": "FunctionDefinition",
            "name": "foo",
            "params": [],
            "ret_ty": {
              "type": "CType",
              "repr": "int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Int" },
            },
            "is_static": false,
            "is_variadic": false,
            "body": {
              "type": "CompoundStmt",
              "items": [
                {
                  "Right": {
                    "type": "Declaration",
                    "kind": {
                      "type": "DeclarationKind",
                      "kind": "VariableDeclaration",
                      "ctype": {
                        "type": "CType",
                        "repr": "enum E",
                        "qualifiers": {
                          "const": false,
                          "volatile": false,
                          "restrict": false,
                          "atomic": false,
                        },
                        "dataKind": {
                          "type": "CTypeDataKind",
                          "kind": "Enum",
                          "name": "E",
                          "members": [],
                        },
                      },
                      "name": "e",
                      "storage": {
                        "static": false,
                        "extern": false,
                        "register": false,
                        "thread_local": false,
                      },
                      "init": {
                        "Some": {
                          "type": "Initializer",
                          "kind": {
                            "type": "InitializerKind",
                            "kind": "AssignExpr",
                            "expr": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Int",
                                "value": "1",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
                                  "restrict": false,
                                  "atomic": false,
                                },
                                "dataKind": {
                                  "type": "CTypeDataKind",
                                  "kind": "Int",
                                },
                              },
                            },
                          },
                        },
                      },
                    },
                  },
                },
                {
                  "Left": {
                    "type": "Statement",
                    "kind": {
                      "type": "StmtKind",
                      "kind": "Return",
                      "expr": {
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Ident",
                          "name": "e",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "enum E",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "Enum",
                            "name": "E",
                            "members": [],
                          },
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
        },
      },
    ],
  })
}
