// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
test "string interpolation, unescaped" {
  let source =
    #|- var riskyBusiness = "<em>Some of the girls are wearing my mother's clothing.</em>";
    #|.quote
    #|p Joel: !{riskyBusiness}
  json_inspect(
    render(source),
    content=(
      #|<div class="quote"></div><p>Joel: <em>Some of the girls are wearing my mother's clothing.</em></p>
    ),
  )
}

// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
/// JS-specific tests for JavaScript expression evaluation
/// This file is only compiled for the JS backend

///|
test "js eval - direct call" {
  // Test that JS FFI works at all
  let locals = Locals::new()
  locals.set("x", "5")
  let result = eval_js_expression("x + 1", locals)
  json_inspect(result, content="6")
}

///|
test "js eval - string method" {
  let locals = Locals::new()
  locals.set("s", "hello")
  let result = eval_js_expression("s.toUpperCase()", locals)
  json_inspect(result, content="HELLO")
}

///|
test "js expression - method call in interpolation" {
  let pug =
    #|p #{msg.toUpperCase()}
  let locals = Locals::new()
  locals.set("msg", "hello")
  json_inspect(render_with_locals(pug, locals), content="<p>HELLO</p>")
}

///|
test "js expression - arithmetic in attribute" {
  let pug =
    #|div(data-value=count + 1)
  let locals = Locals::new()
  locals.set("count", "5")
  // JS backend: numeric 5 + 1 = 6
  json_inspect(
    render_with_locals(pug, locals),
    content="<div data-value=\"6\"></div>",
  )
}

///|
test "js expression - string method chaining" {
  let pug =
    #|p #{name.toLowerCase().trim()}
  let locals = Locals::new()
  locals.set("name", "  HELLO  ")
  json_inspect(render_with_locals(pug, locals), content="<p>hello</p>")
}

///|
test "js expression - ternary with method" {
  let pug =
    #|p= active ? msg.toUpperCase() : msg.toLowerCase()
  let locals = Locals::new()
  locals.set("active", "true")
  locals.set("msg", "Hello")
  json_inspect(render_with_locals(pug, locals), content="<p>HELLO</p>")
}

///|
test "js expression - var assignment simple" {
  let pug =
    #|- var msg = "hello"
    #|p #{msg}
  json_inspect(render(pug), content="<p>hello</p>")
}

///|
test "js expression - var assignment and method" {
  let pug =
    #|- var msg = "not my inside voice"
    #|p This is #{msg.toUpperCase()}
  json_inspect(render(pug), content="<p>This is NOT MY INSIDE VOICE</p>")
}

///|
fn pugjs_default_locals() -> Locals {
  let locals = Locals::new()
  locals.set("title", "Pug")
  locals
}

///|
test "pug/pugjs/cases/attrs-data" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|- var user = { name: 'tobi' }
    #|foo(data-user=user)
    #|foo(data-items=[1,2,3])
    #|foo(data-username='tobi')
    #|foo(data-escaped={message: "Let's rock!"})
    #|foo(data-ampersand={message: "a quote: &quot; this & that"})
    #|foo(data-epoc=new Date(0))
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<foo data-user="{&quot;name&quot;:&quot;tobi&quot;}"></foo><foo data-items="[1,2,3]"></foo><foo data-username="tobi"></foo><foo data-escaped="{&quot;message&quot;:&quot;Let's rock!&quot;}"></foo><foo data-ampersand="{&quot;message&quot;:&quot;a quote: &amp;quot; this &amp; that&quot;}"></foo><foo data-epoc="1970-01-01T00:00:00.000Z"></foo>
    ),
  )
}

///|
test "pug/pugjs/cases/attrs.js" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|- var id = 5
    #|- function answer() { return 42; }
    #|a(href='/user/' + id, class='button')
    #|a(href  =  '/user/' + id, class  =  'button')
    #|meta(key='answer', value=answer())
    #|a(class = ['class1', 'class2'])
    #|a.tag-class(class = ['class1', 'class2'])
    #|
    #|a(href='/user/' + id class='button')
    #|a(href  =  '/user/' + id class  =  'button')
    #|meta(key='answer' value=answer())
    #|a(class = ['class1', 'class2'])
    #|a.tag-class(class = ['class1', 'class2'])
    #|
    #|div(id=id)&attributes({foo: 'bar'})
    #|- var bar = null
    #|div(foo=null bar=bar)&attributes({baz: 'baz'})
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<a class="button" href="/user/5"></a><a class="button" href="/user/5"></a><meta key="answer" value="42"/><a class="class1 class2"></a><a class="tag-class class1 class2"></a><a class="button" href="/user/5"></a><a class="button" href="/user/5"></a><meta key="answer" value="42"/><a class="class1 class2"></a><a class="tag-class class1 class2"></a><div id="5" foo="bar"></div><div baz="baz"></div>
    ),
  )
}

///|
test "pug/pugjs/cases/attrs" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|a(href='/contact') contact
    #|a(href='/save').button save
    #|a(foo, bar, baz)
    #|a(foo='foo, bar, baz', bar=1)
    #|a(foo='((foo))', bar= (1) ? 1 : 0 )
    #|select
    #|  option(value='foo', selected) Foo
    #|  option(selected, value='bar') Bar
    #|a(foo="class:")
    #|input(pattern='\\S+')
    #|
    #|a(href='/contact') contact
    #|a(href='/save').button save
    #|a(foo bar baz)
    #|a(foo='foo, bar, baz' bar=1)
    #|a(foo='((foo))' bar= (1) ? 1 : 0 )
    #|select
    #|  option(value='foo' selected) Foo
    #|  option(selected value='bar') Bar
    #|a(foo="class:")
    #|input(pattern='\\S+')
    #|foo(terse="true")
    #|foo(date=new Date(0))
    #|
    #|foo(abc
    #|   ,def)
    #|foo(abc,
    #|    def)
    #|foo(abc,
    #|		def)
    #|foo(abc
    #|		,def)
    #|foo(abc
    #|		def)
    #|foo(abc
    #|    def)
    #|
    #|- var attrs = {foo: 'bar', bar: '<baz>'}
    #|
    #|div&attributes(attrs)
    #|
    #|a(foo='foo' "bar"="bar")
    #|a(foo='foo' 'bar'='bar')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<a href="/contact">contact</a><a class="button" href="/save">save</a><a foo="foo" bar="bar" baz="baz"></a><a foo="foo, bar, baz" bar="1"></a><a foo="((foo))" bar="1"></a><select><option value="foo" selected="selected">Foo</option><option selected="selected" value="bar">Bar</option></select><a foo="class:"></a><input pattern="\S+"/><a href="/contact">contact</a><a class="button" href="/save">save</a><a foo="foo" bar="bar" baz="baz"></a><a foo="foo, bar, baz" bar="1"></a><a foo="((foo))" bar="1"></a><select><option value="foo" selected="selected">Foo</option><option selected="selected" value="bar">Bar</option></select><a foo="class:"></a><input pattern="\S+"/><foo terse="true"></foo><foo date="1970-01-01T00:00:00.000Z"></foo><foo abc="abc" def="def"></foo><foo abc="abc" def="def"></foo><foo abc="abc" def="def"></foo><foo abc="abc" def="def"></foo><foo abc="abc" def="def"></foo><foo abc="abc" def="def"></foo><div foo="bar" bar="<baz>"></div><a foo="foo" bar="bar"></a><a foo="foo" bar="bar"></a>
    ),
  )
}

///|
test "pug/pugjs/cases/attrs.unescaped" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|script(type='text/x-template')
    #|  div(id!='user-<%= user.id %>')
    #|    h1 <%= user.title %>
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<script type="text/x-template"><div id="user-<%= user.id %>"><h1><%= user.title %></h1></div></script>
    ),
  )
}

///|
test "pug/pugjs/cases/basic" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|html
    #|  body
    #|    h1 Title
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><body><h1>Title</h1></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/blanks" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|
    #|ul
    #|  li foo
    #|
    #|  li bar
    #|      
    #|  li baz
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<ul><li>foo</li><li>bar</li><li>baz</li></ul>
    ),
  )
}

///|
test "pug/pugjs/cases/block-code" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|-
    #|  list = ["uno", "dos", "tres",
    #|          "cuatro", "cinco", "seis"];
    #|//- Without a block, the element is accepted and no code is generated
    #|-
    #|each item in list
    #|  -
    #|    string = item.charAt(0)
    #|    
    #|      .toUpperCase() +
    #|    item.slice(1);
    #|  li= string
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<li>Uno</li><li>Dos</li><li>Tres</li><li>Cuatro</li><li>Cinco</li><li>Seis</li>
    ),
  )
}

///|
test "pug/pugjs/cases/block-expansion" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|ul
    #|  li: a(href='#') foo
    #|  li: a(href='#') bar
    #|
    #|p baz
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<ul><li><a href="#">foo</a></li><li><a href="#">bar</a></li></ul><p>baz</p>
    ),
  )
}

///|
test "pug/pugjs/cases/block-expansion.shorthands" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|ul
    #|  li.list-item: .foo: #bar baz
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<ul><li class="list-item"><div class="foo"><div id="bar">baz</div></div></li></ul>
    ),
  )
}

///|
test "pug/pugjs/cases/blockquote" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|figure
    #|  blockquote
    #|    | Try to define yourself by what you do, and you&#8217;ll burnout every time. You are. That is enough. I rest in that.
    #|  figcaption from @thefray at 1:43pm on May 10
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<figure><blockquote>Try to define yourself by what you do, and you&#8217;ll burnout every time. You are. That is enough. I rest in that.</blockquote><figcaption>from @thefray at 1:43pm on May 10</figcaption></figure>
    ),
  )
}

///|
test "inline text with html entities" {
  inspect(
    @pug.render("p This is plain old <em>text</em> content."),
    content="<p>This is plain old &lt;em&gt;text&lt;/em&gt; content.</p>",
  )
  json_inspect(
    @pug.parse("p This is plain old <em>text</em> content.").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "p",
            "id": "",
            "classes": [],
            "attributes": [],
            "children": [["Text", "This is plain old <em>text</em> content."]],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "piped text single line" {
  let pug =
    #|p
    #|  | This is piped text
  inspect(@pug.render(pug), content="<p>This is piped text</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [["Text", "This is piped text"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "piped text multiple lines" {
  let pug =
    #|p
    #|  | Line one
    #|  | Line two
    #|  | Line three
  inspect(@pug.render(pug), content="<p>Line oneLine twoLine three</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            ["Text", "Line one"],
            ["Text", "Line two"],
            ["Text", "Line three"],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "piped text with inline tag" {
  let pug =
    #|p
    #|  | Click
    #|  a(href="#") here
    #|  | to continue
  inspect(
    @pug.render(pug),
    content="<p>Click<a href=\"#\">here</a>to continue</p>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            ["Text", "Click"],
            [
              "Element",
              {
                "tag": "a",
                "id": "",
                "classes": [],
                "attributes": [
                  { "name": "href", "value": "#", "unescaped": false },
                ],
                "children": [["Text", "here"]],
                "self_closing": false,
              },
            ],
            ["Text", "to continue"],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "block text with dot" {
  let pug =
    #|script.
    #|  console.log('hello');
    #|  console.log('world');
  inspect(
    @pug.render(pug),
    content="<script>console.log('hello');\nconsole.log('world');</script>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "script",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [["Text", "console.log('hello');\nconsole.log('world');"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "style block text" {
  let pug =
    #|style.
    #|  body {
    #|    color: red;
    #|  }
  inspect(@pug.render(pug), content="<style>body {\n  color: red;\n}</style>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "style",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [["Text", "body {\n  color: red;\n}"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "pre block preserves whitespace" {
  let pug =
    #|pre.
    #|  function hello() {
    #|    return 'world';
    #|  }
  inspect(
    @pug.render(pug),
    content="<pre>function hello() {\n  return 'world';\n}</pre>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "pre",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [["Text", "function hello() {\n  return 'world';\n}"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "simple tag" {
  inspect(@pug.render("div"), content="<div></div>")
  json_inspect(@pug.parse("div").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "tag with text" {
  inspect(@pug.render("p Hello World"), content="<p>Hello World</p>")
  json_inspect(@pug.parse("p Hello World").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [["Text", "Hello World"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "tag with id" {
  inspect(@pug.render("div#main"), content="<div id=\"main\"></div>")
  json_inspect(@pug.parse("div#main").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "main",
          "classes": [],
          "attributes": [],
          "children": [],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "tag with class" {
  inspect(
    @pug.render("div.container"),
    content="<div class=\"container\"></div>",
  )
  json_inspect(@pug.parse("div.container").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": ["container"],
          "attributes": [],
          "children": [],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "tag with multiple classes" {
  inspect(
    @pug.render("div.foo.bar.baz"),
    content="<div class=\"foo bar baz\"></div>",
  )
  json_inspect(@pug.parse("div.foo.bar.baz").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": ["foo", "bar", "baz"],
          "attributes": [],
          "children": [],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "tag with id and classes" {
  inspect(
    @pug.render("div#main.container.active"),
    content="<div id=\"main\" class=\"container active\"></div>",
  )
  json_inspect(@pug.parse("div#main.container.active").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "main",
          "classes": ["container", "active"],
          "attributes": [],
          "children": [],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "implicit div with id" {
  inspect(@pug.render("#main"), content="<div id=\"main\"></div>")
  json_inspect(@pug.parse("#main").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "main",
          "classes": [],
          "attributes": [],
          "children": [],
          "self_closing": false,
        },
      ],
    ],
  })
}
