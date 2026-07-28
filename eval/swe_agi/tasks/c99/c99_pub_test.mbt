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
test "simple prim expr/int literal" {
  let code =
    #|int foo() { return 42; }
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
test "simple prim expr/float literal" {
  let code =
    #|float foo() { return 42.0f; }
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
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Float",
                          "value": "42",
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
test "simple prim expr/double literal" {
  let code =
    #|double foo() { return 42.0; }
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
              "repr": "double",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Double" },
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
                          "kind": "Double",
                          "value": "42",
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
test "compelete program/is_prime" {
  let code =
    #|int printf(const char *format, ...);
    #|
    #|int is_prime(int n) {
    #|  if (n <= 1) return 0;
    #|  for (int i = 2; i * i <= n; i++) {
    #|    if (n % i == 0) return 0;
    #|  }
    #|  return 1;
    #|}
    #|
    #|int main() {
    #|  printf("11 is prime: %d\n", is_prime(11));
    #|  printf("12 is prime: %d\n", is_prime(12));
    #|  printf("13 is prime: %d\n", is_prime(13));
    #|  printf("14 is prime: %d\n", is_prime(14));
    #|  printf("15 is prime: %d\n", is_prime(15));
    #|  printf("16 is prime: %d\n", is_prime(16));
    #|  printf("17 is prime: %d\n", is_prime(17));
    #|  printf("18 is prime: %d\n", is_prime(18));
    #|  printf("19 is prime: %d\n", is_prime(19));
    #|  printf("20 is prime: %d\n", is_prime(20));
    #|  return 0;
    #|}
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
                "repr": "int (const char * format, ...)",
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
                      "name": "format",
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
            "name": "is_prime",
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
                "name": "n",
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
                          "type": "RelationalExpr",
                          "kind": {
                            "type": "RelationalExprKind",
                            "kind": "LEExpr",
                            "lhs": {
                              "type": "PrimExpr",
                              "kind": {
                                "type": "PrimExprKind",
                                "kind": "Ident",
                                "name": "n",
                              },
                              "ctype": {
                                "type": "CType",
                                "repr": "int",
                                "qualifiers": {
                                  "const": false,
                                  "volatile": false,
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
                            ],
                          },
                        },
                        "cond": {
                          "Some": {
                            "type": "RelationalExpr",
                            "kind": {
                              "type": "RelationalExprKind",
                              "kind": "LEExpr",
                              "lhs": {
                                "type": "MultiExpr",
                                "kind": {
                                  "type": "MultiExprKind",
                                  "kind": "MulExpr",
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
                              "rhs": {
                                "type": "PrimExpr",
                                "kind": {
                                  "type": "PrimExprKind",
                                  "kind": "Ident",
                                  "name": "n",
                                },
                                "ctype": {
                                  "type": "CType",
                                  "repr": "int",
                                  "qualifiers": {
                                    "const": false,
                                    "volatile": false,
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
                                      "kind": "If",
                                      "stmt": {
                                        "type": "IfStmt",
                                        "cond": {
                                          "type": "EqualityExpr",
                                          "kind": {
                                            "type": "EqualityExprKind",
                                            "kind": "EQExpr",
                                            "lhs": {
                                              "type": "MultiExpr",
                                              "kind": {
                                                "type": "MultiExprKind",
                                                "kind": "ModExpr",
                                                "lhs": {
                                                  "type": "PrimExpr",
                                                  "kind": {
                                                    "type": "PrimExprKind",
                                                    "kind": "Ident",
                                                    "name": "n",
                                                  },
                                                  "ctype": {
                                                    "type": "CType",
                                                    "repr": "int",
                                                    "qualifiers": {
                                                      "const": false,
                                                      "volatile": false,
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
                                        "else": { "None": true },
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
            "name": "main",
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
                      "kind": "Expr",
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
                              "repr": "int (const char * format, ...)",
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
                                    "name": "format",
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
                                "value": ["11 is prime: %d\n"],
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
                              "type": "PostfixExpr",
                              "kind": {
                                "type": "PostfixExprKind",
                                "kind": "FuncCall",
                                "callee": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "is_prime",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int (int n)",
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
                                          "name": "n",
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
                                      "value": "11",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
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
                              "repr": "int (const char * format, ...)",
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
                                    "name": "format",
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
                                "value": ["12 is prime: %d\n"],
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
                              "type": "PostfixExpr",
                              "kind": {
                                "type": "PostfixExprKind",
                                "kind": "FuncCall",
                                "callee": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "is_prime",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int (int n)",
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
                                          "name": "n",
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
                                      "value": "12",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
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
                              "repr": "int (const char * format, ...)",
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
                                    "name": "format",
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
                                "value": ["13 is prime: %d\n"],
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
                              "type": "PostfixExpr",
                              "kind": {
                                "type": "PostfixExprKind",
                                "kind": "FuncCall",
                                "callee": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "is_prime",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int (int n)",
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
                                          "name": "n",
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
                                      "value": "13",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
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
                              "repr": "int (const char * format, ...)",
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
                                    "name": "format",
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
                                "value": ["14 is prime: %d\n"],
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
                              "type": "PostfixExpr",
                              "kind": {
                                "type": "PostfixExprKind",
                                "kind": "FuncCall",
                                "callee": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "is_prime",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int (int n)",
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
                                          "name": "n",
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
                                      "value": "14",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
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
                              "repr": "int (const char * format, ...)",
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
                                    "name": "format",
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
                                "value": ["15 is prime: %d\n"],
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
                              "type": "PostfixExpr",
                              "kind": {
                                "type": "PostfixExprKind",
                                "kind": "FuncCall",
                                "callee": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "is_prime",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int (int n)",
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
                                          "name": "n",
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
                                      "value": "15",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
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
                              "repr": "int (const char * format, ...)",
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
                                    "name": "format",
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
                                "value": ["16 is prime: %d\n"],
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
                              "type": "PostfixExpr",
                              "kind": {
                                "type": "PostfixExprKind",
                                "kind": "FuncCall",
                                "callee": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "is_prime",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int (int n)",
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
                                          "name": "n",
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
                                      "value": "16",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
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
                              "repr": "int (const char * format, ...)",
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
                                    "name": "format",
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
                                "value": ["17 is prime: %d\n"],
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
                              "type": "PostfixExpr",
                              "kind": {
                                "type": "PostfixExprKind",
                                "kind": "FuncCall",
                                "callee": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "is_prime",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int (int n)",
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
                                          "name": "n",
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
                                      "value": "17",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
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
                              "repr": "int (const char * format, ...)",
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
                                    "name": "format",
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
                                "value": ["18 is prime: %d\n"],
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
                              "type": "PostfixExpr",
                              "kind": {
                                "type": "PostfixExprKind",
                                "kind": "FuncCall",
                                "callee": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "is_prime",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int (int n)",
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
                                          "name": "n",
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
                                      "value": "18",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
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
                              "repr": "int (const char * format, ...)",
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
                                    "name": "format",
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
                                "value": ["19 is prime: %d\n"],
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
                              "type": "PostfixExpr",
                              "kind": {
                                "type": "PostfixExprKind",
                                "kind": "FuncCall",
                                "callee": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "is_prime",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int (int n)",
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
                                          "name": "n",
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
                                      "value": "19",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
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
                              "repr": "int (const char * format, ...)",
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
                                    "name": "format",
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
                                "value": ["20 is prime: %d\n"],
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
                              "type": "PostfixExpr",
                              "kind": {
                                "type": "PostfixExprKind",
                                "kind": "FuncCall",
                                "callee": {
                                  "type": "PrimExpr",
                                  "kind": {
                                    "type": "PrimExprKind",
                                    "kind": "Ident",
                                    "name": "is_prime",
                                  },
                                  "ctype": {
                                    "type": "CType",
                                    "repr": "int (int n)",
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
                                          "name": "n",
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
                                      "value": "20",
                                    },
                                    "ctype": {
                                      "type": "CType",
                                      "repr": "int",
                                      "qualifiers": {
                                        "const": false,
                                        "volatile": false,
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
test "prim expr/long literal" {
  let code =
    #|long foo() { return 42l; }
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
                        "type": "PrimExpr",
                        "kind": {
                          "type": "PrimExprKind",
                          "kind": "Long",
                          "value": "42",
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
test "prim expr/long long literal" {
  let code =
    #|long long foo() { return 42ll; }
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
              "repr": "long long",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "LongLong" },
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
                          "kind": "LongLong",
                          "value": "42",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "long long",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "LongLong",
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
test "prim expr/unsigned int literal" {
  let code =
    #|unsigned int foo() { return 42u; }
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
              "repr": "unsigned int",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "UInt" },
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
                          "kind": "UInt",
                          "value": "42",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "unsigned int",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "UInt",
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
test "prim expr/unsigned long literal" {
  let code =
    #|unsigned long foo() { return 42ul; }
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
              "repr": "unsigned long",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "ULong" },
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
                          "kind": "ULong",
                          "value": "42",
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
test "prim expr/unsigned long long literal" {
  let code =
    #|unsigned long long foo() { return 42ull; }
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
              "repr": "unsigned long long",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "ULongLong" },
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
                          "kind": "ULongLong",
                          "value": "42",
                        },
                        "ctype": {
                          "type": "CType",
                          "repr": "unsigned long long",
                          "qualifiers": {
                            "const": false,
                            "volatile": false,
                            "restrict": false,
                            "atomic": false,
                          },
                          "dataKind": {
                            "type": "CTypeDataKind",
                            "kind": "ULongLong",
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
test "prim expr/char literal" {
  let code =
    #|char foo() { return 'c'; }
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
              "repr": "char",
              "qualifiers": {
                "const": false,
                "volatile": false,
                "restrict": false,
                "atomic": false,
              },
              "dataKind": { "type": "CTypeDataKind", "kind": "Char" },
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
                          "value": "c",
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
test "prim expr/string literal" {
  let code =
    #|const char *foo() { return "hello"; }
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
                          "value": ["hello"],
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
test "prim expr/string literal concatenation" {
  let code =
    #|const char *foo() { return "hello" " world"; }
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
                          "value": ["hello", " world"],
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
