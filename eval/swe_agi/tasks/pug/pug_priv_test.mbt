///|
test "pug/pugjs/cases/blocks-in-blocks" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "./auxiliary/blocks-in-blocks-layout",
    (
      #|doctype html
      #|html
      #|  head
      #|    title Default title
      #|  body
      #|    block body
      #|      .container
      #|        block content
      #|
    ),
  )
  registry.register(
    "./auxiliary/blocks-in-blocks-layout.pug",
    (
      #|doctype html
      #|html
      #|  head
      #|    title Default title
      #|  body
      #|    block body
      #|      .container
      #|        block content
      #|
    ),
  )
  registry.register(
    "auxiliary/blocks-in-blocks-layout.pug",
    (
      #|doctype html
      #|html
      #|  head
      #|    title Default title
      #|  body
      #|    block body
      #|      .container
      #|        block content
      #|
    ),
  )
  let pug =
    #|extends ./auxiliary/blocks-in-blocks-layout.pug
    #|
    #|block body
    #|  h1 Page 2
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<!DOCTYPE html><html><head><title>Default title</title></head><body><h1>Page 2</h1></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/blocks-in-if" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|//- see https://github.com/pugjs/pug/issues/1589
    #|
    #|-var ajax = true
    #|
    #|-if( ajax )
    #|    //- return only contents if ajax requests
    #|    block contents
    #|        p ajax contents
    #|
    #|-else
    #|    //- return all html
    #|    doctype html
    #|    html
    #|        head
    #|            meta( charset='utf8' )
    #|            title sample
    #|            body
    #|                block contents
    #|                    p all contetns
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p>ajax contents</p>
    ),
  )
}

///|
test "pug/pugjs/cases/case-blocks" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|html
    #|  body
    #|    - var friends = 1
    #|    case friends
    #|      when 0
    #|        p you have no friends
    #|      when 1
    #|        p you have a friend
    #|      default
    #|        p you have #{friends} friends
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><body><p>you have a friend</p></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/case" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|html
    #|  body
    #|    - var friends = 1
    #|    case friends
    #|      when 0: p you have no friends
    #|      when 1: p you have a friend
    #|      default: p you have #{friends} friends
    #|    - var friends = 0
    #|    case friends
    #|      when 0
    #|      when 1
    #|        p you have very few friends
    #|      default
    #|        p you have #{friends} friends
    #|
    #|    - var friend = 'Tim:G'
    #|    case friend
    #|      when 'Tim:G':    p Friend is a string
    #|      when {tim: 'g'}: p Friend is an object
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><body><p>you have a friend</p><p>you have very few friends</p><p>Friend is a string</p></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/classes-empty" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|a(class='')
    #|a(class=null)
    #|a(class=undefined)
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<a></a><a></a><a></a>
    ),
  )
}

///|
test "pug/pugjs/cases/classes" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|a(class=['foo', 'bar', 'baz'])
    #|
    #|
    #|
    #|a.foo(class='bar').baz
    #|
    #|
    #|
    #|a.foo-bar_baz
    #|
    #|a(class={foo: true, bar: false, baz: true})
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<a class="foo bar baz"></a><a class="foo bar baz"></a><a class="foo-bar_baz"></a><a class="foo baz"></a>
    ),
  )
}

///|
test "pug/pugjs/cases/code.conditionals" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|- if (true)
    #|  p foo
    #|- else
    #|  p bar
    #|
    #|- if (true) {
    #|  p foo
    #|- } else {
    #|  p bar
    #|- }
    #|
    #|if true
    #|  p foo
    #|  p bar
    #|  p baz
    #|else
    #|  p bar
    #|
    #|unless true
    #|  p foo
    #|else
    #|  p bar
    #|
    #|if 'nested'
    #|  if 'works'
    #|    p yay
    #|
    #|//- allow empty blocks
    #|if false
    #|else
    #|  .bar
    #|if true
    #|  .bar
    #|else
    #|.bing
    #|
    #|if false
    #|  .bing
    #|else if false
    #|  .bar
    #|else
    #|  .foo
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p>foo</p><p>foo</p><p>foo</p><p>bar</p><p>baz</p><p>bar</p><p>yay</p><div class="bar"></div><div class="bar"></div><div class="bing"></div><div class="foo"></div>
    ),
  )
}

///|
test "pug/pugjs/cases/code.escape" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|p= '<script>'
    #|p!= '<script>'
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p>&lt;script&gt;</p><p><script></p>
    ),
  )
}

///|
test "pug/pugjs/cases/code.iteration" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|- var items = [1,2,3]
    #|
    #|ul
    #|  - items.forEach(function(item){
    #|    li= item
    #|  - })
    #|
    #|- var items = [1,2,3]
    #|
    #|ul
    #|  for item, i in items
    #|    li(class='item-' + i)= item
    #|
    #|ul
    #|  each item, i in items
    #|    li= item
    #|
    #|ul
    #|  each $item in items
    #|    li= $item
    #|
    #|- var nums = [1, 2, 3]
    #|- var letters = ['a', 'b', 'c']
    #|
    #|ul
    #|  for l in letters
    #|    for n in nums
    #|      li #{n}: #{l}
    #|
    #|- var count = 1
    #|- var counter = function() { return [count++, count++, count++] }
    #|ul
    #|  for n in counter()
    #|    li #{n}
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<ul><li>1</li><li>2</li><li>3</li></ul><ul><li class="item-0">1</li><li class="item-1">2</li><li class="item-2">3</li></ul><ul><li>1</li><li>2</li><li>3</li></ul><ul><li>1</li><li>2</li><li>3</li></ul><ul><li>1: a</li><li>2: a</li><li>3: a</li><li>1: b</li><li>2: b</li><li>3: b</li><li>1: c</li><li>2: c</li><li>3: c</li></ul><ul><li>1</li><li>2</li><li>3</li></ul>
    ),
  )
}

///|
test "pug/pugjs/cases/code" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|p= null
    #|p= undefined
    #|p= ''
    #|p= 0
    #|p= false
    #|p(foo=null)
    #|p(foo=undefined)
    #|p(foo='')
    #|p(foo=0)
    #|p(foo=false)
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p></p><p></p><p></p><p>0</p><p>false</p><p></p><p></p><p foo=""></p><p foo="0"></p><p></p>
    ),
  )
}

///|
test "pug/pugjs/cases/comments-in-case" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|doctype html
    #|html
    #|  body
    #|   - var s = 'this'
    #|   case s
    #|     //- Comment
    #|     when 'this'
    #|       p It's this!
    #|     when 'that'
    #|       p It's that!
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<!DOCTYPE html><html><body><p>It's this!</p></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/comments" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|// foo
    #|ul
    #|  // bar
    #|  li one
    #|  // baz
    #|  li two
    #|
    #|//
    #|  ul
    #|    li foo
    #|
    #|// block
    #|  // inline follow
    #|  li three
    #|
    #|// block
    #|  // inline followed by tags
    #|  ul
    #|    li four
    #|
    #|//if IE lt 9
    #|  // inline
    #|  script(src='/lame.js')
    #|  // end-inline
    #|
    #|p five
    #|
    #|.foo // not a comment
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<!-- foo--><ul><!-- bar--><li>one</li><!-- baz--><li>two</li></ul><!--
      #|ul
      #|  li foo
      #|
      #|--><!-- block
      #|// inline follow
      #|li three
      #|
      #|--><!-- block
      #|// inline followed by tags
      #|ul
      #|  li four
      #|
      #|--><!--if IE lt 9
      #|// inline
      #|script(src='/lame.js')
      #|// end-inline
      #|
      #|--><p>five</p><div class="foo">// not a comment</div>
    ),
  )
}

///|
test "pug/pugjs/cases/comments.source" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|//-
    #|  s/s.
    #|
    #|//- test/cases/comments.source.pug
    #|
    #|//-
    #|  test/cases/comments.source.pug
    #|  when
    #|  ()
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|
    ),
  )
}

///|
test "pug/pugjs/cases/doctype.custom" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|doctype custom stuff
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<!DOCTYPE custom stuff>
    ),
  )
}

///|
test "pug/pugjs/cases/doctype.default" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|doctype
    #|html
    #|  body
    #|    h1 Title
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<!DOCTYPE html><html><body><h1>Title</h1></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/doctype.keyword" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|doctype html
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<!DOCTYPE html>
    ),
  )
}

///|
test "pug/pugjs/cases/each.else" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|- var users = []
    #|
    #|ul
    #|  for user in users
    #|    li= user.name
    #|  else
    #|    li no users!
    #|
    #|
    #|- var users = [{ name: 'tobi', friends: ['loki'] }, { name: 'loki' }]
    #|
    #|if users
    #|  ul
    #|    for user in users
    #|      li= user.name
    #|    else
    #|      li no users!
    #|
    #|- var user = { name: 'tobi', age: 10 }
    #|
    #|ul
    #|  each val, key in user
    #|    li #{key}: #{val}
    #|  else
    #|    li user has no details!
    #|
    #|- var user = {}
    #|
    #|ul
    #|  each prop, key in user
    #|    li #{key}: #{val}
    #|  else
    #|    li user has no details!
    #|
    #|- var user = Object.create(null)
    #|- user.name = 'tobi'
    #|
    #|ul
    #|  each val, key in user
    #|    li #{key}: #{val}
    #|  else
    #|    li user has no details!
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<ul><li>no users!</li></ul><ul><li>tobi</li><li>loki</li></ul><ul><li>name: tobi</li><li>age: 10</li></ul><ul><li>user has no details!</li></ul><ul><li>name: tobi</li></ul>
    ),
  )
}

///|
test "pug/pugjs/cases/escape-chars" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|script.
    #|  var re = /\d+/;
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<script>var re = /\d+/;</script>
    ),
  )
}

///|
test "pug/pugjs/cases/escape-test" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|doctype html
    #|html
    #|    head
    #|        title escape-test
    #|    body
    #|        textarea
    #|            - var txt = '<param name="flashvars" value="a=&quot;value_a&quot;&b=&quot;value_b&quot;&c=3"/>'
    #|            | #{txt}
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<!DOCTYPE html><html><head><title>escape-test</title></head><body><textarea>&lt;param name=&quot;flashvars&quot; value=&quot;a=&amp;quot;value_a&amp;quot;&amp;b=&amp;quot;value_b&amp;quot;&amp;c=3&quot;/&gt;</textarea></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/escaping-class-attribute" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|foo(attr="<%= bar %>")
    #|foo(class="<%= bar %>")
    #|foo(attr!="<%= bar %>")
    #|foo(class!="<%= bar %>")
    #|foo(class!="<%= bar %> lol rofl")
    #|foo(class!="<%= bar %> lol rofl <%= lmao %>")
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<foo attr="&lt;%= bar %&gt;"></foo><foo class="&lt;%= bar %&gt;"></foo><foo attr="<%= bar %>"></foo><foo class="<%= bar %>"></foo><foo class="<%= bar %> lol rofl"></foo><foo class="<%= bar %> lol rofl <%= lmao %>"></foo>
    ),
  )
}

///|
test "pug/pugjs/cases/filter-in-include" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "./auxiliary/filter-in-include",
    (
      #|html
      #|  head
      #|    style(type="text/css")
      #|      :less
      #|        @pad: 15px;
      #|        body {
      #|          padding: @pad;
      #|        }
      #|
    ),
  )
  registry.register(
    "./auxiliary/filter-in-include.pug",
    (
      #|html
      #|  head
      #|    style(type="text/css")
      #|      :less
      #|        @pad: 15px;
      #|        body {
      #|          padding: @pad;
      #|        }
      #|
    ),
  )
  registry.register(
    "auxiliary/filter-in-include.pug",
    (
      #|html
      #|  head
      #|    style(type="text/css")
      #|      :less
      #|        @pad: 15px;
      #|        body {
      #|          padding: @pad;
      #|        }
      #|
    ),
  )
  let pug =
    #|include ./auxiliary/filter-in-include.pug
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><style type="text/css">body {
      #|  padding: 15px;
      #|}
      #|</style></head></html>
    ),
  )
}

///|
test "pug/pugjs/cases/filters.inline" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|p before #[:cdata inside] after
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p>
      #|  before <![CDATA[inside]]> after</p>
    ),
  )
}

///|
test "pug/pugjs/cases/html" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|- var version = 1449104952939
    #|
    #|<ul>
    #|  <li>foo</li>
    #|  <li>bar</li>
    #|  <li>baz</li>
    #|</ul>
    #|
    #|<!--build:js /js/app.min.js?v=#{version}-->
    #|<!--endbuild-->
    #|
    #|p You can <em>embed</em> html as well.
    #|p: <strong>Even</strong> as the body of a block expansion.
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<ul><li>foo</li><li>bar</li><li>baz</li></ul><!--build:js /js/app.min.js?v=1449104952939--><!--endbuild--><p>You can <em>embed</em> html as well.</p><p><strong>Even</strong> as the body of a block expansion.</p>
    ),
  )
}

///|
test "pug/pugjs/cases/html5" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|doctype html
    #|input(type='checkbox', checked)
    #|input(type='checkbox', checked=true)
    #|input(type='checkbox', checked=false)
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<!DOCTYPE html><input type="checkbox" checked><input type="checkbox" checked><input type="checkbox">
    ),
  )
}

///|
test "pug/pugjs/cases/include-extends-from-root" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "/auxiliary/extends-from-root",
    (
      #|extends /auxiliary/layout.pug
      #|
      #|block content
      #|    include /auxiliary/include-from-root.pug
      #|
    ),
  )
  registry.register(
    "/auxiliary/extends-from-root.pug",
    (
      #|extends /auxiliary/layout.pug
      #|
      #|block content
      #|    include /auxiliary/include-from-root.pug
      #|
    ),
  )
  registry.register(
    "/auxiliary/include-from-root",
    (
      #|h1 hello
    ),
  )
  registry.register(
    "/auxiliary/include-from-root.pug",
    (
      #|h1 hello
    ),
  )
  registry.register(
    "/auxiliary/layout",
    (
      #|html
      #|  head
      #|    title My Application
      #|    block head
      #|  body
      #|    block content
    ),
  )
  registry.register(
    "/auxiliary/layout.pug",
    (
      #|html
      #|  head
      #|    title My Application
      #|    block head
      #|  body
      #|    block content
    ),
  )
  registry.register(
    "auxiliary/extends-from-root.pug",
    (
      #|extends /auxiliary/layout.pug
      #|
      #|block content
      #|    include /auxiliary/include-from-root.pug
      #|
    ),
  )
  registry.register(
    "auxiliary/include-from-root.pug",
    (
      #|h1 hello
    ),
  )
  registry.register(
    "auxiliary/layout.pug",
    (
      #|html
      #|  head
      #|    title My Application
      #|    block head
      #|  body
      #|    block content
    ),
  )
  let pug =
    #|include /auxiliary/extends-from-root.pug
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><title>My Application</title></head><body><h1>hello</h1></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/include-extends-of-common-template" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "auxiliary/extends-empty-block-1",
    (
      #|extends empty-block.pug
      #|
      #|block test
      #|    div test1
      #|
      #|
    ),
  )
  registry.register(
    "auxiliary/extends-empty-block-1.pug",
    (
      #|extends empty-block.pug
      #|
      #|block test
      #|    div test1
      #|
      #|
    ),
  )
  registry.register(
    "auxiliary/extends-empty-block-2",
    (
      #|extends empty-block.pug
      #|
      #|block test
      #|    div test2
      #|
      #|
    ),
  )
  registry.register(
    "auxiliary/extends-empty-block-2.pug",
    (
      #|extends empty-block.pug
      #|
      #|block test
      #|    div test2
      #|
      #|
    ),
  )
  registry.register(
    "empty-block",
    (
      #|block test
      #|
      #|
    ),
  )
  registry.register(
    "empty-block.pug",
    (
      #|block test
      #|
      #|
    ),
  )
  let pug =
    #|include auxiliary/extends-empty-block-1.pug
    #|include auxiliary/extends-empty-block-2.pug
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<div>test1</div><div>test2</div>
    ),
  )
}

///|
test "pug/pugjs/cases/include-extends-relative" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "../../cases/auxiliary/include-from-root",
    (
      #|h1 hello
    ),
  )
  registry.register(
    "../../cases/auxiliary/include-from-root.pug",
    (
      #|h1 hello
    ),
  )
  registry.register(
    "../../cases/auxiliary/layout",
    (
      #|html
      #|  head
      #|    title My Application
      #|    block head
      #|  body
      #|    block content
    ),
  )
  registry.register(
    "../../cases/auxiliary/layout.pug",
    (
      #|html
      #|  head
      #|    title My Application
      #|    block head
      #|  body
      #|    block content
    ),
  )
  registry.register(
    "../cases/auxiliary/extends-relative",
    (
      #|extends ../../cases/auxiliary/layout
      #|
      #|block content
      #|    include ../../cases/auxiliary/include-from-root
      #|
    ),
  )
  registry.register(
    "../cases/auxiliary/extends-relative.pug",
    (
      #|extends ../../cases/auxiliary/layout
      #|
      #|block content
      #|    include ../../cases/auxiliary/include-from-root
      #|
    ),
  )
  let pug =
    #|include ../cases/auxiliary/extends-relative.pug
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><title>My Application</title></head><body><h1>hello</h1></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/include-only-text-body" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|| The message is "
    #|yield
    #|| "
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|The message is ""
    ),
  )
}

///|
test "pug/pugjs/cases/include-only-text" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "include-only-text-body",
    (
      #|| The message is "
      #|yield
      #|| "
      #|
    ),
  )
  registry.register(
    "include-only-text-body.pug",
    (
      #|| The message is "
      #|yield
      #|| "
      #|
    ),
  )
  let pug =
    #|html
    #|  body
    #|    p
    #|      include include-only-text-body.pug
    #|        em hello world
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><body><p>The message is "<em>hello world</em>"</p></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/include-with-text-head" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|head
    #|  script(type='text/javascript').
    #|    alert('hello world');
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<head><script type="text/javascript">alert('hello world');</script></head>
    ),
  )
}

///|
test "pug/pugjs/cases/include-with-text" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "include-with-text-head",
    (
      #|head
      #|  script(type='text/javascript').
      #|    alert('hello world');
      #|
    ),
  )
  registry.register(
    "include-with-text-head.pug",
    (
      #|head
      #|  script(type='text/javascript').
      #|    alert('hello world');
      #|
    ),
  )
  let pug =
    #|html
    #|  include include-with-text-head.pug
    #|    script(src='/caustic.js')
    #|    script(src='/app.js')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><script type="text/javascript">alert('hello world');</script><script src="/caustic.js"></script><script src="/app.js"></script></head></html>
    ),
  )
}

///|
test "pug/pugjs/cases/include.script" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "auxiliary/pet",
    (
      #|.pet
      #|  h1 {{name}}
      #|  p {{name}} is a {{species}} that is {{age}} old
    ),
  )
  registry.register(
    "auxiliary/pet.pug",
    (
      #|.pet
      #|  h1 {{name}}
      #|  p {{name}} is a {{species}} that is {{age}} old
    ),
  )
  let pug =
    #|script#pet-template(type='text/x-template')
    #|  include auxiliary/pet.pug
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<script id="pet-template" type="text/x-template"><div class="pet"><h1>{{name}}</h1><p>{{name}} is a {{species}} that is {{age}} old</p></div></script>
    ),
  )
}

///|
test "pug/pugjs/cases/include.yield.nested" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "auxiliary/yield-nested",
    (
      #|html
      #|  head
      #|    title
      #|  body
      #|    h1 Page
      #|    #content
      #|      #content-wrapper
      #|        yield
      #|    #footer
      #|      stuff
    ),
  )
  registry.register(
    "auxiliary/yield-nested.pug",
    (
      #|html
      #|  head
      #|    title
      #|  body
      #|    h1 Page
      #|    #content
      #|      #content-wrapper
      #|        yield
      #|    #footer
      #|      stuff
    ),
  )
  let pug =
    #|
    #|include auxiliary/yield-nested.pug
    #|  p some content
    #|  p and some more
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><title></title></head><body><h1>Page</h1><div id="content"><div id="content-wrapper"><p>some content</p><p>and some more</p></div></div><div id="footer"><stuff></stuff></div></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/includes-with-ext-js" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "javascript-new-lines.js",
    (
      #|var x = '\n here is some \n new lined text';
      #|
    ),
  )
  registry.register(
    "javascript-new-lines.js.pug",
    (
      #|var x = '\n here is some \n new lined text';
      #|
    ),
  )
  let pug =
    #|pre
    #|  code
    #|    include javascript-new-lines.js
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<pre><code>var x = '\n here is some \n new lined text';
      #|</code></pre>
    ),
  )
}

///|
test "pug/pugjs/cases/inheritance.alert-dialog" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "auxiliary/dialog",
    (
      #|
      #|extends window.pug
      #|
      #|block window-content
      #|  .dialog
      #|    block content
      #|
    ),
  )
  registry.register(
    "auxiliary/dialog.pug",
    (
      #|
      #|extends window.pug
      #|
      #|block window-content
      #|  .dialog
      #|    block content
      #|
    ),
  )
  registry.register(
    "window",
    (
      #|
      #|.window
      #|  a(href='#').close Close
      #|  block window-content
    ),
  )
  registry.register(
    "window.pug",
    (
      #|
      #|.window
      #|  a(href='#').close Close
      #|  block window-content
    ),
  )
  let pug =
    #|
    #|extends auxiliary/dialog.pug
    #|
    #|block content
    #|  h1 Alert!
    #|  p I'm an alert!
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<div class="window"><a class="close" href="#">Close</a><div class="dialog"><h1>Alert!</h1><p>I'm an alert!</p></div></div>
    ),
  )
}

///|
test "pug/pugjs/cases/inheritance.defaults" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|html
    #|  head
    #|    block head
    #|      script(src='jquery.js')
    #|      script(src='keymaster.js')
    #|      script(src='caustic.js')
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><script src="jquery.js"></script><script src="keymaster.js"></script><script src="caustic.js"></script></head></html>
    ),
  )
}

///|
test "pug/pugjs/cases/inheritance.extend.include" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|extend auxiliary/layout.include.pug
    #|
    #|block head
    #|  script(src='jquery.js')
    #|
    #|block content
    #|  h2 Page
    #|  p Some content
    #|
    #|block window-content
    #|  h2 Awesome
    #|  p Now we can extend included blocks!
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><title>My Application</title><script src="jquery.js"></script></head><body><h2>Page</h2><p>Some content</p><div class="window"><a class="close" href="#">Close</a><h2>Awesome</h2><p>Now we can extend included blocks!</p></div></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/inheritance.extend.mixins.block" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|extend auxiliary/inheritance.extend.mixin.block.pug
    #|
    #|block content
    #|  p Hello World!
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><title>My Application</title></head><body><article><p>Hello World!</p></article></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/inheritance.extend.mixins" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|extend auxiliary/layout.pug
    #|
    #|mixin article(title)
    #|  if title
    #|    h1= title
    #|  block
    #|
    #|block content
    #|  +article("The meaning of life")
    #|    p Foo bar baz!
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><title>My Application</title></head><body><h1>The meaning of life</h1><p>Foo bar baz!</p></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/inheritance.extend" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|extend auxiliary/layout.pug
    #|
    #|block head
    #|  script(src='jquery.js')
    #|
    #|block content
    #|  h2 Page
    #|  p Some content
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><title>My Application</title><script src="jquery.js"></script></head><body><h2>Page</h2><p>Some content</p></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/inheritance.extend.recursive" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "/auxiliary/inheritance.extend.recursive-parent",
    (
      #|extends inheritance.extend.recursive-grandparent.pug
      #|
      #|block grandparent
      #|    h3 parent
      #|    block parent
    ),
  )
  registry.register(
    "/auxiliary/inheritance.extend.recursive-parent.pug",
    (
      #|extends inheritance.extend.recursive-grandparent.pug
      #|
      #|block grandparent
      #|    h3 parent
      #|    block parent
    ),
  )
  registry.register(
    "auxiliary/inheritance.extend.recursive-parent.pug",
    (
      #|extends inheritance.extend.recursive-grandparent.pug
      #|
      #|block grandparent
      #|    h3 parent
      #|    block parent
    ),
  )
  registry.register(
    "inheritance.extend.recursive-grand-grandparent",
    (
      #|h1 grand-grandparent
      #|block grand-grandparent
    ),
  )
  registry.register(
    "inheritance.extend.recursive-grand-grandparent.pug",
    (
      #|h1 grand-grandparent
      #|block grand-grandparent
    ),
  )
  registry.register(
    "inheritance.extend.recursive-grandparent",
    (
      #|extends inheritance.extend.recursive-grand-grandparent.pug
      #|
      #|block grand-grandparent
      #|    h2 grandparent
      #|    block grandparent
      #|
      #|
    ),
  )
  registry.register(
    "inheritance.extend.recursive-grandparent.pug",
    (
      #|extends inheritance.extend.recursive-grand-grandparent.pug
      #|
      #|block grand-grandparent
      #|    h2 grandparent
      #|    block grandparent
      #|
      #|
    ),
  )
  let pug =
    #|extends /auxiliary/inheritance.extend.recursive-parent.pug
    #|
    #|block parent
    #|    h4 child
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<h1>grand-grandparent</h1><h2>grandparent</h2><h3>parent</h3><h4>child</h4>
    ),
  )
}

///|
test "pug/pugjs/cases/inheritance.extend.whitespace" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|extend auxiliary/layout.pug
    #|
    #|block head
    #|
    #|  script(src='jquery.js')
    #|
    #|block content
    #|  
    #|    
    #|  
    #|  h2 Page
    #|  p Some content
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><title>My Application</title><script src="jquery.js"></script></head><body><h2>Page</h2><p>Some content</p></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/inheritance" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "auxiliary/layout",
    (
      #|html
      #|  head
      #|    title My Application
      #|    block head
      #|  body
      #|    block content
    ),
  )
  registry.register(
    "auxiliary/layout.pug",
    (
      #|html
      #|  head
      #|    title My Application
      #|    block head
      #|  body
      #|    block content
    ),
  )
  let pug =
    #|
    #|extends auxiliary/layout.pug
    #|
    #|block head
    #|  script(src='jquery.js')
    #|
    #|block content
    #|  h2 Page
    #|  p Some content
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><title>My Application</title><script src="jquery.js"></script></head><body><h2>Page</h2><p>Some content</p></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/inline-tag" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|p bing #[strong foo] bong
    #|
    #|p.
    #|  bing
    #|  #[strong foo]
    #|  #[strong= '[foo]']
    #|  #[- var foo = 'foo]']
    #|  bong
    #|
    #|p
    #|  | bing
    #|  | #[strong foo]
    #|  | #[strong= '[foo]']
    #|  | #[- var foo = 'foo]']
    #|  | bong
    #|
    #|p.
    #|  \#[strong escaped]
    #|  \#[#[strong escaped]
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p>bing <strong>foo</strong> bong</p><p>
      #|  bing
      #|  <strong>foo</strong><strong>[foo]</strong>
      #|  
      #|  bong
      #|  
      #|</p><p>
      #|  bing
      #|  <strong>foo</strong><strong>[foo]</strong>
      #|  
      #|  bong
      #|</p><p>
      #|  #[strong escaped]
      #|  #[<strong>escaped</strong></p>
    ),
  )
}

///|
test "pug/pugjs/cases/intepolated-elements" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|p #[a.rho(href='#', class='rho--modifier') with inline link]
    #|p Some text #[a.rho(href='#', class='rho--modifier')]
    #|p Some text #[a.rho(href='#', class='rho--modifier') with inline link]
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p><a class="rho rho--modifier" href="#">with inline link</a></p><p>Some text <a class="rho rho--modifier" href="#"></a></p><p>Some text <a class="rho rho--modifier" href="#">with inline link</a></p>
    ),
  )
}

///|
test "pug/pugjs/cases/interpolated-mixin" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|mixin linkit(url)
    #|  a(href=url)= url
    #|
    #|p This also works #[+linkit('http://www.bing.com')] so hurrah for Pug
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p>This also works <a href="http://www.bing.com">http://www.bing.com</a> so hurrah for Pug
      #|</p>
    ),
  )
}

///|
test "pug/pugjs/cases/interpolation.escape" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|- var id = 42;
    #|foo
    #|  | some
    #|  | \#{text}
    #|  | here
    #|  | My ID #{"is {" + id + "}"}
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<foo>
      #|  some
      #|  #{text}
      #|  here
      #|  My ID is {42}
      #|</foo>
    ),
  )
}

///|
test "pug/pugjs/cases/layout.append" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "../fixtures/append/app-layout",
    (
      #|
      #|extends layout
      #|
      #|block append head
      #|  script(src='app.js')
    ),
  )
  registry.register(
    "../fixtures/append/app-layout.pug",
    (
      #|
      #|extends layout
      #|
      #|block append head
      #|  script(src='app.js')
    ),
  )
  registry.register(
    "layout",
    (
      #|
      #|html
      #|  block head
      #|    script(src='vendor/jquery.js')
      #|    script(src='vendor/caustic.js')
      #|  body
      #|    block body
    ),
  )
  registry.register(
    "layout.pug",
    (
      #|
      #|html
      #|  block head
      #|    script(src='vendor/jquery.js')
      #|    script(src='vendor/caustic.js')
      #|  body
      #|    block body
    ),
  )
  let pug =
    #|
    #|extends ../fixtures/append/app-layout.pug
    #|
    #|block append head
    #|  script(src='foo.js')
    #|  script(src='bar.js')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><script src="vendor/jquery.js"></script><script src="vendor/caustic.js"></script><script src="app.js"></script><script src="foo.js"></script><script src="bar.js"></script><body></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/layout.append.without-block" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "../fixtures/append-without-block/app-layout",
    (
      #|
      #|extends layout.pug
      #|
      #|append head
      #|  script(src='app.js')
      #|
    ),
  )
  registry.register(
    "../fixtures/append-without-block/app-layout.pug",
    (
      #|
      #|extends layout.pug
      #|
      #|append head
      #|  script(src='app.js')
      #|
    ),
  )
  registry.register(
    "layout",
    (
      #|
      #|html
      #|  block head
      #|    script(src='vendor/jquery.js')
      #|    script(src='vendor/caustic.js')
      #|  body
      #|    block body
    ),
  )
  registry.register(
    "layout.pug",
    (
      #|
      #|html
      #|  block head
      #|    script(src='vendor/jquery.js')
      #|    script(src='vendor/caustic.js')
      #|  body
      #|    block body
    ),
  )
  let pug =
    #|
    #|extends ../fixtures/append-without-block/app-layout.pug
    #|
    #|append head
    #|  script(src='foo.js')
    #|  script(src='bar.js')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><script src="vendor/jquery.js"></script><script src="vendor/caustic.js"></script><script src="app.js"></script><script src="foo.js"></script><script src="bar.js"></script><body></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/layout.multi.append.prepend.block" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "../fixtures/multi-append-prepend-block/redefine",
    (
      #|extends root.pug
      #|
      #|block content
      #|	.content
      #|		| Defined content
      #|
    ),
  )
  registry.register(
    "../fixtures/multi-append-prepend-block/redefine.pug",
    (
      #|extends root.pug
      #|
      #|block content
      #|	.content
      #|		| Defined content
      #|
    ),
  )
  registry.register(
    "root",
    (
      #|block content
      #|	| default content
      #|
      #|block head
      #|	script(src='/app.js')
    ),
  )
  registry.register(
    "root.pug",
    (
      #|block content
      #|	| default content
      #|
      #|block head
      #|	script(src='/app.js')
    ),
  )
  let pug =
    #|extends ../fixtures/multi-append-prepend-block/redefine.pug
    #|
    #|append content
    #|	p.first.append Something appended to content
    #|
    #|prepend content
    #|	p.first.prepend Something prepended to content
    #|
    #|append content
    #|	p.last.append Last append must be most last
    #|
    #|prepend content
    #|	p.last.prepend Last prepend must appear at top
    #|
    #|append head
    #|	script(src='jquery.js')
    #|
    #|prepend head
    #|	script(src='foo.js')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p class="last prepend">Last prepend must appear at top</p><p class="first prepend">Something prepended to content</p><div class="content">Defined content</div><p class="first append">Something appended to content</p><p class="last append">Last append must be most last</p><script src="foo.js"></script><script src="/app.js"></script><script src="jquery.js"></script>
    ),
  )
}

///|
test "pug/pugjs/cases/layout.prepend" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "../fixtures/prepend/app-layout",
    (
      #|
      #|extends layout.pug
      #|
      #|block prepend head
      #|  script(src='app.js')
      #|
    ),
  )
  registry.register(
    "../fixtures/prepend/app-layout.pug",
    (
      #|
      #|extends layout.pug
      #|
      #|block prepend head
      #|  script(src='app.js')
      #|
    ),
  )
  registry.register(
    "layout",
    (
      #|
      #|html
      #|  block head
      #|    script(src='vendor/jquery.js')
      #|    script(src='vendor/caustic.js')
      #|  body
      #|    block body
    ),
  )
  registry.register(
    "layout.pug",
    (
      #|
      #|html
      #|  block head
      #|    script(src='vendor/jquery.js')
      #|    script(src='vendor/caustic.js')
      #|  body
      #|    block body
    ),
  )
  let pug =
    #|
    #|extends ../fixtures/prepend/app-layout.pug
    #|
    #|block prepend head
    #|  script(src='foo.js')
    #|  script(src='bar.js')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><script src="foo.js"></script><script src="bar.js"></script><script src="app.js"></script><script src="vendor/jquery.js"></script><script src="vendor/caustic.js"></script><body></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/layout.prepend.without-block" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "../fixtures/prepend-without-block/app-layout",
    (
      #|
      #|extends layout.pug
      #|
      #|prepend head
      #|  script(src='app.js')
      #|
    ),
  )
  registry.register(
    "../fixtures/prepend-without-block/app-layout.pug",
    (
      #|
      #|extends layout.pug
      #|
      #|prepend head
      #|  script(src='app.js')
      #|
    ),
  )
  registry.register(
    "layout",
    (
      #|
      #|html
      #|  block head
      #|    script(src='vendor/jquery.js')
      #|    script(src='vendor/caustic.js')
      #|  body
      #|    block body
    ),
  )
  registry.register(
    "layout.pug",
    (
      #|
      #|html
      #|  block head
      #|    script(src='vendor/jquery.js')
      #|    script(src='vendor/caustic.js')
      #|  body
      #|    block body
    ),
  )
  let pug =
    #|
    #|extends ../fixtures/prepend-without-block/app-layout.pug
    #|
    #|prepend head
    #|  script(src='foo.js')
    #|  script(src='bar.js')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><script src="foo.js"></script><script src="bar.js"></script><script src="app.js"></script><script src="vendor/jquery.js"></script><script src="vendor/caustic.js"></script><body></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/mixin-at-end-of-file" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "./auxiliary/mixin-at-end-of-file",
    (
      #|mixin slide
      #|  section.slide
      #|    block
    ),
  )
  registry.register(
    "./auxiliary/mixin-at-end-of-file.pug",
    (
      #|mixin slide
      #|  section.slide
      #|    block
    ),
  )
  registry.register(
    "auxiliary/mixin-at-end-of-file.pug",
    (
      #|mixin slide
      #|  section.slide
      #|    block
    ),
  )
  let pug =
    #|include ./auxiliary/mixin-at-end-of-file.pug
    #|
    #|+slide()
    #|  p some awesome content
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<section class="slide"><p>some awesome content</p></section>
    ),
  )
}

///|
test "pug/pugjs/cases/mixin-block-with-space" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|mixin m(id)
    #|  div
    #|    block    
    #|
    #|+m()
    #|  | This text should appear
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<div>This text should appear
      #|</div>
    ),
  )
}

///|
test "pug/pugjs/cases/mixin-hoist" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|mixin foo()
    #|  h1= title
    #|
    #|html
    #|  body
    #|    +foo
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><body><h1>Pug</h1></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/mixin-via-include" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "../fixtures/mixin-include",
    (
      #|mixin bang
      #|  +foo
      #|
      #|mixin foo
      #|  p bar
    ),
  )
  registry.register(
    "../fixtures/mixin-include.pug",
    (
      #|mixin bang
      #|  +foo
      #|
      #|mixin foo
      #|  p bar
    ),
  )
  let pug =
    #|//- regression test for https://github.com/pugjs/pug/issues/1435
    #|
    #|include ../fixtures/mixin-include.pug
    #|
    #|+bang
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p>bar</p>
    ),
  )
}

///|
test "pug/pugjs/cases/mixin.attrs" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|mixin centered(title)
    #|  div.centered(id=attributes.id)
    #|    - if (title)
    #|      h1(class=attributes.class)= title
    #|    block
    #|    - if (attributes.href)
    #|      .footer
    #|        a(href=attributes.href) Back
    #|
    #|mixin main(title)
    #|  div.stretch
    #|    +centered(title).highlight&attributes(attributes)
    #|      block
    #|
    #|mixin bottom
    #|  div.bottom&attributes(attributes)
    #|    block
    #|
    #|body
    #|  +centered#First Hello World
    #|  +centered('Section 1')#Second
    #|    p Some important content.
    #|  +centered('Section 2')#Third.foo(href='menu.html', class='bar')
    #|    p Even more important content.
    #|  +main('Section 3')(href='#')
    #|    p Last content.
    #|  +bottom.foo(class='bar', name='end', id='Last', data-attr='baz')
    #|    p Some final words.
    #|  +bottom(class=['class1', 'class2'])
    #|
    #|mixin foo
    #|  div.thing(attr1='foo', attr2='bar')&attributes(attributes)
    #|
    #|- var val = '<biz>'
    #|- var classes = ['foo', 'bar']
    #|+foo(attr3='baz' data-foo=val data-bar!=val class=classes).thunk
    #|
    #|//- Regression test for #1424
    #|mixin work_filmstrip_item(work)
    #|  div&attributes(attributes)= work
    #|+work_filmstrip_item('work')("data-profile"='profile', "data-creator-name"='name')
    #|
    #|mixin my-mixin(arg1, arg2, arg3, arg4)
    #|  p= arg1
    #|  p= arg2
    #|  p= arg3
    #|  p= arg4
    #|
    #|+foo(
    #|  attr3="qux"
    #|  class="baz"
    #|)
    #|
    #|+my-mixin(
    #|'1',
    #|      '2',
    #|  '3',
    #|      '4'
    #|)
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<body><div class="centered" id="First">Hello World
      #|  </div><div class="centered" id="Second"><h1>Section 1</h1><p>Some important content.</p></div><div class="centered" id="Third"><h1 class="foo bar">Section 2</h1><p>Even more important content.</p><div class="footer"><a href="menu.html">Back</a></div></div><div class="stretch"><div class="centered"><h1 class="highlight">Section 3</h1><p>Last content.</p><div class="footer"><a href="#">Back</a></div></div></div><div class="bottom foo bar" name="end" id="Last" data-attr="baz"><p>Some final words.</p></div><div class="bottom class1 class2"></div></body><div class="thing foo bar thunk" attr1="foo" attr2="bar" attr3="baz" data-foo="&lt;biz&gt;" data-bar="<biz>"></div><div data-profile="profile" data-creator-name="name">work</div><div class="thing baz" attr1="foo" attr2="bar" attr3="qux"></div><p>1</p><p>2</p><p>3</p><p>4</p>
    ),
  )
}

///|
test "pug/pugjs/cases/mixin.block-tag-behaviour" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|mixin article(name)
    #|  section.article
    #|    h1= name
    #|    block
    #|
    #|html
    #|  body
    #|    +article('Foo'): p I'm article foo
    #|
    #|mixin article(name)
    #|  section.article
    #|    h1= name
    #|    p
    #|      block
    #|
    #|html
    #|  body
    #|    +article('Something').
    #|      I'm a much longer
    #|      text-only article,
    #|      but you can still
    #|      inline html tags
    #|      in me if you want.
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><body><section class="article"><h1>Foo</h1><p>I'm article foo</p></section></body></html><html><body><section class="article"><h1>Something</h1><p>
      #|        I'm a much longer
      #|        text-only article,
      #|        but you can still
      #|        inline html tags
      #|        in me if you want.
      #|      </p></section></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/mixin.blocks" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|
    #|mixin form(method, action)
    #|  form(method=method, action=action)
    #|    - var csrf_token_from_somewhere = 'hey'
    #|    input(type='hidden', name='_csrf', value=csrf_token_from_somewhere)
    #|    block
    #|
    #|html
    #|  body
    #|    +form('GET', '/search')
    #|      input(type='text', name='query', placeholder='Search')
    #|      input(type='submit', value='Search')
    #|
    #|html
    #|  body
    #|    +form('POST', '/search')
    #|      input(type='text', name='query', placeholder='Search')
    #|      input(type='submit', value='Search')
    #|
    #|html
    #|  body
    #|    +form('POST', '/search')
    #|
    #|mixin bar()
    #|  #bar
    #|    block
    #|
    #|mixin foo()
    #|  #foo
    #|    +bar
    #|      block
    #|
    #|+foo
    #|  p one
    #|  p two
    #|  p three
    #|
    #|
    #|mixin baz
    #|    #baz
    #|        block
    #|
    #|+baz()= '123'
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><body><form method="GET" action="/search"><input type="hidden" name="_csrf" value="hey"/><input type="text" name="query" placeholder="Search"/><input type="submit" value="Search"/></form></body></html><html><body><form method="POST" action="/search"><input type="hidden" name="_csrf" value="hey"/><input type="text" name="query" placeholder="Search"/><input type="submit" value="Search"/></form></body></html><html><body><form method="POST" action="/search"><input type="hidden" name="_csrf" value="hey"/></form></body></html><div id="foo"><div id="bar"><p>one</p><p>two</p><p>three</p></div></div><div id="baz">123
      #|</div>
    ),
  )
}

///|
test "pug/pugjs/cases/mixin.merge" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|mixin foo
    #|  p.bar&attributes(attributes) One
    #|  p.baz.quux&attributes(attributes) Two
    #|  p&attributes(attributes) Three
    #|  p.bar&attributes(attributes)(class="baz") Four
    #|
    #|body
    #|  +foo.hello
    #|  +foo#world
    #|  +foo.hello#world
    #|  +foo.hello.world
    #|  +foo(class="hello")
    #|  +foo.hello(class="world")
    #|  +foo
    #|  +foo&attributes({class: "hello"})
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<body><p class="bar hello">One</p><p class="baz quux hello">Two</p><p class="hello">Three</p><p class="bar baz hello">Four</p><p class="bar" id="world">One</p><p class="baz quux" id="world">Two</p><p id="world">Three</p><p class="bar baz" id="world">Four</p><p class="bar hello" id="world">One</p><p class="baz quux hello" id="world">Two</p><p class="hello" id="world">Three</p><p class="bar baz hello" id="world">Four</p><p class="bar hello world">One</p><p class="baz quux hello world">Two</p><p class="hello world">Three</p><p class="bar baz hello world">Four</p><p class="bar hello">One</p><p class="baz quux hello">Two</p><p class="hello">Three</p><p class="bar baz hello">Four</p><p class="bar hello world">One</p><p class="baz quux hello world">Two</p><p class="hello world">Three</p><p class="bar baz hello world">Four</p><p class="bar">One</p><p class="baz quux">Two</p><p>Three</p><p class="bar baz">Four</p><p class="bar hello">One</p><p class="baz quux hello">Two</p><p class="hello">Three</p><p class="bar baz hello">Four</p></body>
    ),
  )
}

///|
test "pug/pugjs/cases/mixins-unused" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|mixin never-called
    #|  .wtf This isn't something we ever want to output
    #|body
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<body></body>
    ),
  )
}

///|
test "pug/pugjs/cases/mixins" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|mixin comment(title, str)
    #|  .comment
    #|    h2= title
    #|    p.body= str
    #|
    #|
    #|mixin comment (title, str)
    #|  .comment
    #|    h2= title
    #|    p.body= str
    #|
    #|#user
    #|  h1 Tobi
    #|  .comments
    #|    +comment('This',
    #|            (('is regular, javascript')))
    #|
    #|mixin list
    #|  ul
    #|    li foo
    #|    li bar
    #|    li baz
    #|
    #|body
    #|  +list()
    #|  + list()
    #|
    #|mixin foobar(str)
    #|  div#interpolation= str + 'interpolated'
    #|
    #|- var suffix = "bar"
    #|+#{'foo' + suffix}('This is ')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<div id="user"><h1>Tobi</h1><div class="comments"><div class="comment"><h2>This</h2><p class="body">is regular, javascript</p></div></div></div><body><ul><li>foo</li><li>bar</li><li>baz</li></ul><ul><li>foo</li><li>bar</li><li>baz</li></ul></body><div id="interpolation">This is interpolated</div>
    ),
  )
}

///|
test "pug/pugjs/cases/mixins.rest-args" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|mixin list(tag, ...items)
    #|  #{tag}
    #|    each item in items
    #|      li= item
    #|
    #|+list('ul', 1, 2, 3, 4)
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<ul><li>1</li><li>2</li><li>3</li><li>4</li></ul>
    ),
  )
}

///|
test "pug/pugjs/cases/namespaces" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|fb:user:role Something
    #|foo(fb:foo='bar')
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<fb:user:role>Something</fb:user:role><foo fb:foo="bar"></foo>
    ),
  )
}

///|
test "pug/pugjs/cases/nesting" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|ul
    #|  li a
    #|  li b
    #|  li
    #|    ul
    #|        li c
    #|        li d
    #|  li e
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<ul><li>a</li><li>b</li><li><ul><li>c</li><li>d</li></ul></li><li>e</li></ul>
    ),
  )
}

///|
test "pug/pugjs/cases/pipeless-comments" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|//
    #|       .foo
    #|  	.bar
    #|  .hey
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<!--
      #|     .foo
      #|	.bar
      #|.hey
      #|-->
    ),
  )
}

///|
test "pug/pugjs/cases/pipeless-tag" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|pre.
    #|    what
    #|  is #{'going'} #[| #{'on'}]
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<pre>  what
      #|is going on</pre>
    ),
  )
}

///|
test "pug/pugjs/cases/pre" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|pre.
    #|  foo
    #|  bar
    #|  baz
    #|
    #|pre
    #|  code.
    #|    foo
    #|    bar
    #|    baz
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<pre>foo
      #|bar
      #|baz
      #|</pre><pre><code>foo
      #|bar
      #|baz</code></pre>
    ),
  )
}

///|
test "pug/pugjs/cases/quotes" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|p "foo"
    #|p 'foo'
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p>"foo"</p><p>'foo'</p>
    ),
  )
}

///|
test "pug/pugjs/cases/regression.1794" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "./auxiliary/1794-extends",
    (
      #|block content
    ),
  )
  registry.register(
    "./auxiliary/1794-extends.pug",
    (
      #|block content
    ),
  )
  registry.register(
    "./auxiliary/1794-include",
    (
      #|mixin test()
      #|  .test&attributes(attributes)
      #| 
      #|+test()
    ),
  )
  registry.register(
    "./auxiliary/1794-include.pug",
    (
      #|mixin test()
      #|  .test&attributes(attributes)
      #| 
      #|+test()
    ),
  )
  registry.register(
    "auxiliary/1794-extends.pug",
    (
      #|block content
    ),
  )
  registry.register(
    "auxiliary/1794-include.pug",
    (
      #|mixin test()
      #|  .test&attributes(attributes)
      #| 
      #|+test()
    ),
  )
  let pug =
    #|extends ./auxiliary/1794-extends.pug
    #| 
    #|block content
    #|  include ./auxiliary/1794-include.pug
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<div class="test"></div>
    ),
  )
}

///|
test "pug/pugjs/cases/regression.784" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|- var url = 'http://www.google.com'
    #|.url #{url.replace('http://', '').replace(/^www\./, '')}
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<div class="url">google.com</div>
    ),
  )
}

///|
test "pug/pugjs/cases/script.whitespace" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|script.
    #|  if (foo) {
    #|    
    #|    bar();
    #|  
    #|  }
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<script>
      #|  if (foo) {
      #|    
      #|    bar();
      #|  
      #|  }
      #|</script>
    ),
  )
}

///|
test "pug/pugjs/cases/scripts.non-js" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|script#user-template(type='text/template')
    #|  #user
    #|    h1 <%= user.name %>
    #|    p <%= user.description %>
    #|
    #|script#user-template(type='text/template').
    #|  if (foo) {
    #|    bar();
    #|  }
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<script id="user-template" type="text/template"><div id="user"><h1><%= user.name %></h1><p><%= user.description %></p></div></script><script id="user-template" type="text/template">
      #|  if (foo) {
      #|    bar();
      #|  }
      #|</script>
    ),
  )
}

///|
test "pug/pugjs/cases/scripts" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|script.
    #|  if (foo) {
    #|    bar();
    #|  }
    #|script!= 'foo()'
    #|script foo()
    #|script
    #|div
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<script>
      #|  if (foo) {
      #|    bar();
      #|  }
      #|</script><script>foo()</script><script>foo()</script><script></script><div></div>
    ),
  )
}

///|
test "pug/pugjs/cases/self-closing-html" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|doctype html
    #|html
    #|  body
    #|    br/
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<!DOCTYPE html><html><body><br/></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/single-period" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|span .
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<span>.</span>
    ),
  )
}

///|
test "pug/pugjs/cases/source" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|html
    #|  audio(preload='auto', autobuffer, controls)
    #|    source(src='foo')
    #|    source(src='bar')
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><audio preload="auto" autobuffer="autobuffer" controls="controls"><source src="foo"/><source src="bar"/></audio></html>
    ),
  )
}

///|
test "pug/pugjs/cases/styles" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|html
    #|  head
    #|    style.
    #|      body {
    #|        padding: 50px;
    #|      }
    #|  body
    #|    div(style='color:red;background:green')
    #|    div(style={color: 'red', background: 'green'})
    #|    div&attributes({style: 'color:red;background:green'})
    #|    div&attributes({style: {color: 'red', background: 'green'}})
    #|    mixin div()
    #|      div&attributes(attributes)
    #|    +div(style='color:red;background:green')
    #|    +div(style={color: 'red', background: 'green'})
    #|    - var bg = 'green';
    #|    div(style={color: 'red', background: bg})
    #|    div&attributes({style: {color: 'red', background: bg}})
    #|    +div(style={color: 'red', background: bg})
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><head><style>
      #|      body {
      #|        padding: 50px;
      #|      }
      #|    </style></head><body><div style="color:red;background:green"></div><div style="color:red;background:green;"></div><div style="color:red;background:green"></div><div style="color:red;background:green;"></div><div style="color:red;background:green"></div><div style="color:red;background:green;"></div><div style="color:red;background:green;"></div><div style="color:red;background:green;"></div><div style="color:red;background:green;"></div></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/tag.interpolation" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|- var tag = 'p'
    #|- var foo = 'bar'
    #|
    #|#{tag} value
    #|#{tag}(foo='bar') value
    #|#{foo ? 'a' : 'li'}(something) here
    #|
    #|mixin item(icon)
    #|  li
    #|    if attributes.href
    #|      a&attributes(attributes)
    #|        img.icon(src=icon)
    #|        block
    #|    else
    #|      span&attributes(attributes)
    #|        img.icon(src=icon)
    #|        block
    #|
    #|ul
    #|  +item('contact') Contact
    #|  +item(href='/contact') Contact
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p>value</p><p foo="bar">value</p><a something="something">here</a><ul><li><span><img class="icon" src="contact"/>Contact</span></li><li><a href="/contact"><img class="icon"/>Contact</a></li></ul>
    ),
  )
}

///|
test "pug/pugjs/cases/tags.self-closing" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|body
    #|  foo
    #|  foo(bar='baz')
    #|  foo/
    #|  foo(bar='baz')/
    #|  foo /
    #|  foo(bar='baz') /
    #|  #{'foo'}/
    #|  #{'foo'}(bar='baz')/
    #|  #{'foo'} /
    #|  #{'foo'}(bar='baz') /
    #|  //- can have a single space after them
    #|  img 
    #|  //- can have lots of white space after them
    #|  img    
    #|  #{
    #|    'foo'
    #|  }/
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<body><foo></foo><foo bar="baz"></foo><foo/><foo bar="baz"/><foo>/</foo><foo bar="baz">/</foo><foo/><foo bar="baz"/><foo>/</foo><foo bar="baz">/</foo><img/><img/><foo/></body>
    ),
  )
}

///|
test "pug/pugjs/cases/template" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|script(type='text/x-template')
    #|  article
    #|    h2 {{title}}
    #|    p {{description}}
    #|
    #|script(type='text/x-template').
    #|  article
    #|    h2 {{title}}
    #|    p {{description}}
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<script type="text/x-template"><article><h2>{{title}}</h2><p>{{description}}</p></article></script><script type="text/x-template">
      #|  article
      #|    h2 {{title}}
      #|    p {{description}}
      #|</script>
    ),
  )
}

///|
test "pug/pugjs/cases/text-block" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|
    #|label Username:
    #|  input(type='text', name='user[name]')
    #|
    #|label Password:
    #|  input(type='text', name='user[pass]')
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<label>Username:
      #|  <input type="text" name="user[name]"/></label><label>Password:
      #|  <input type="text" name="user[pass]"/></label>
    ),
  )
}

///|
test "pug/pugjs/cases/text" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|option(value='') -- (selected) --
    #|
    #|p
    #|
    #|p.
    #|
    #|p
    #|  | foo
    #|  | bar
    #|  |
    #|  |
    #|  | baz
    #|
    #|p.
    #|  foo
    #|
    #|
    #|  bar
    #|  baz
    #|
    #|.
    #|
    #|.
    #|  foo
    #|
    #|
    #|  bar
    #|  baz
    #|
    #|pre
    #|  | foo
    #|  |   bar
    #|  |     baz
    #|  | .
    #|
    #|pre.
    #|  foo
    #|    bar
    #|      baz
    #|  .
    #|
    #|.
    #|  foo
    #|    bar
    #|      baz
    #|  .
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<option value="">-- (selected) --</option><p></p><p></p><p>
      #|  foo
      #|  bar
      #|  
      #|  
      #|  baz
      #|</p><p>
      #|  foo
      #|  
      #|  
      #|  bar
      #|  baz
      #|  
      #|</p>foo
      #|
      #|
      #|bar
      #|baz
      #|
      #|<pre>foo
      #|  bar
      #|    baz
      #|.</pre><pre>foo
      #|  bar
      #|    baz
      #|.
      #|</pre>foo
      #|  bar
      #|    baz
      #|.
    ),
  )
}

///|
test "pug/pugjs/cases/utf8bom" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|﻿p "foo"
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<p>"foo"</p>
    ),
  )
}

///|
test "pug/pugjs/cases/vars" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|- var foo = 'bar'
    #|- var list = [1,2,3]
    #|a(class=list, id=foo)
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<a class="1 2 3" id="bar"></a>
    ),
  )
}

///|
test "pug/pugjs/cases/while" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|- var x = 1;
    #|ul
    #|  while x < 10
    #|    - x++;
    #|    li= x
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<ul><li>2</li><li>3</li><li>4</li><li>5</li><li>6</li><li>7</li><li>8</li><li>9</li><li>10</li></ul>
    ),
  )
}

///|
test "pug/pugjs/cases/xml" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|doctype xml
    #|category(term='some term')/
    #|link http://google.com
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<?xml version="1.0" encoding="utf-8" ?><category term="some term"/><link>http://google.com</link>
    ),
  )
}

///|
test "pug/pugjs/cases/yield-before-conditional-head" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|head
    #|  script(src='/jquery.js')
    #|  yield
    #|  if false
    #|    script(src='/jquery.ui.js')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<head><script src="/jquery.js"></script></head>
    ),
  )
}

///|
test "pug/pugjs/cases/yield-before-conditional" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "yield-before-conditional-head",
    (
      #|head
      #|  script(src='/jquery.js')
      #|  yield
      #|  if false
      #|    script(src='/jquery.ui.js')
      #|
    ),
  )
  registry.register(
    "yield-before-conditional-head.pug",
    (
      #|head
      #|  script(src='/jquery.js')
      #|  yield
      #|  if false
      #|    script(src='/jquery.ui.js')
      #|
    ),
  )
  let pug =
    #|html
    #|  body
    #|    include yield-before-conditional-head.pug
    #|      script(src='/caustic.js')
    #|      script(src='/app.js')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><body><head><script src="/jquery.js"></script><script src="/caustic.js"></script><script src="/app.js"></script></head></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/yield-head" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|head
    #|  script(src='/jquery.js')
    #|  yield
    #|  script(src='/jquery.ui.js')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<head><script src="/jquery.js"></script><script src="/jquery.ui.js"></script></head>
    ),
  )
}

///|
test "pug/pugjs/cases/yield-title-head" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|head
    #|  title
    #|    yield
    #|  script(src='/jquery.js')
    #|  script(src='/jquery.ui.js')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<head><title></title><script src="/jquery.js"></script><script src="/jquery.ui.js"></script></head>
    ),
  )
}

///|
test "pug/pugjs/cases/yield-title" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "yield-title-head",
    (
      #|head
      #|  title
      #|    yield
      #|  script(src='/jquery.js')
      #|  script(src='/jquery.ui.js')
      #|
    ),
  )
  registry.register(
    "yield-title-head.pug",
    (
      #|head
      #|  title
      #|    yield
      #|  script(src='/jquery.js')
      #|  script(src='/jquery.ui.js')
      #|
    ),
  )
  let pug =
    #|html
    #|  body
    #|    include yield-title-head.pug
    #|      | My Title
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><body><head><title>My Title</title><script src="/jquery.js"></script><script src="/jquery.ui.js"></script></head></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases/yield" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  registry.register(
    "yield-head",
    (
      #|head
      #|  script(src='/jquery.js')
      #|  yield
      #|  script(src='/jquery.ui.js')
      #|
    ),
  )
  registry.register(
    "yield-head.pug",
    (
      #|head
      #|  script(src='/jquery.js')
      #|  yield
      #|  script(src='/jquery.ui.js')
      #|
    ),
  )
  let pug =
    #|html
    #|  body
    #|    include yield-head.pug
    #|      script(src='/caustic.js')
    #|      script(src='/app.js')
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<html><body><head><script src="/jquery.js"></script><script src="/caustic.js"></script><script src="/app.js"></script><script src="/jquery.ui.js"></script></head></body></html>
    ),
  )
}

///|
test "pug/pugjs/cases-es2015/attr" {
  let locals = pugjs_default_locals()
  let registry = TemplateRegistry::new()
  let pug =
    #|- var avatar = '219b77f9d21de75e81851b6b886057c7'
    #|
    #|div.avatar-div(style=`background-image: url(https://www.gravatar.com/avatar/${avatar})`)
    #|
  inspect(
    render_with_registry(pug, locals, registry).trim(),
    content=(
      #|<div class="avatar-div" style="background-image: url(https://www.gravatar.com/avatar/219b77f9d21de75e81851b6b886057c7)"></div>
    ),
  )
}

///|
test "implicit div with class" {
  inspect(@pug.render(".container"), content="<div class=\"container\"></div>")
  json_inspect(@pug.parse(".container").to_test_json(), content={
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
test "tag with attributes" {
  inspect(
    @pug.render("a(href=\"https://example.com\") Click me"),
    content="<a href=\"https://example.com\">Click me</a>",
  )
  json_inspect(
    @pug.parse("a(href=\"https://example.com\") Click me").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "a",
            "id": "",
            "classes": [],
            "attributes": [
              {
                "name": "href",
                "value": "https://example.com",
                "unescaped": false,
              },
            ],
            "children": [["Text", "Click me"]],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "tag with multiple attributes" {
  inspect(
    @pug.render(
      "input(type=\"text\", name=\"username\", placeholder=\"Enter name\")",
    ),
    content="<input type=\"text\" name=\"username\" placeholder=\"Enter name\">",
  )
  json_inspect(
    @pug.parse(
      "input(type=\"text\", name=\"username\", placeholder=\"Enter name\")",
    ).to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "input",
            "id": "",
            "classes": [],
            "attributes": [
              { "name": "type", "value": "text", "unescaped": false },
              { "name": "name", "value": "username", "unescaped": false },
              {
                "name": "placeholder",
                "value": "Enter name",
                "unescaped": false,
              },
            ],
            "children": [],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "void element" {
  inspect(@pug.render("br"), content="<br>")
  json_inspect(@pug.parse("br").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "br",
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
test "img element" {
  inspect(
    @pug.render("img(src=\"photo.jpg\", alt=\"A photo\")"),
    content="<img src=\"photo.jpg\" alt=\"A photo\">",
  )
  json_inspect(
    @pug.parse("img(src=\"photo.jpg\", alt=\"A photo\")").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "img",
            "id": "",
            "classes": [],
            "attributes": [
              { "name": "src", "value": "photo.jpg", "unescaped": false },
              { "name": "alt", "value": "A photo", "unescaped": false },
            ],
            "children": [],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "doctype" {
  inspect(@pug.render("doctype html"), content="<!DOCTYPE html>")
  json_inspect(@pug.parse("doctype html").to_test_json(), content={
    "nodes": [["Doctype", "html"]],
  })
}

///|
test "comment" {
  inspect(
    @pug.render("// This is a comment"),
    content="<!--This is a comment-->",
  )
  json_inspect(@pug.parse("// This is a comment").to_test_json(), content={
    "nodes": [["Comment", { "text": "This is a comment", "render": true }]],
  })
}

///|
test "nested elements" {
  let pug =
    #|div
    #|  p Hello
    #|  p World
  inspect(@pug.render(pug), content="<div><p>Hello</p><p>World</p></div>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Hello"]],
                "self_closing": false,
              },
            ],
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "World"]],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "deeply nested elements" {
  let pug =
    #|html
    #|  head
    #|    title My Page
    #|  body
    #|    h1 Welcome
  inspect(
    @pug.render(pug),
    content="<html><head><title>My Page</title></head><body><h1>Welcome</h1></body></html>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "html",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "head",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  [
                    "Element",
                    {
                      "tag": "title",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "My Page"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
            [
              "Element",
              {
                "tag": "body",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  [
                    "Element",
                    {
                      "tag": "h1",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "Welcome"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "pretty print" {
  let pug =
    #|div
    #|  p Hello
  let expected =
    #|<div>
    #|  <p>Hello</p>
    #|</div>
    #|
  inspect(@pug.render_pretty(pug), content=expected)
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Hello"]],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "full html page" {
  let pug =
    #|doctype html
    #|html
    #|  head
    #|    meta(charset="utf-8")
    #|    title Example
    #|  body
    #|    h1#title.heading Welcome
    #|    p.intro This is a paragraph.
  inspect(
    @pug.render(pug),
    content="<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Example</title></head><body><h1 id=\"title\" class=\"heading\">Welcome</h1><p class=\"intro\">This is a paragraph.</p></body></html>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      ["Doctype", "html"],
      [
        "Element",
        {
          "tag": "html",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "head",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  [
                    "Element",
                    {
                      "tag": "meta",
                      "id": "",
                      "classes": [],
                      "attributes": [
                        {
                          "name": "charset",
                          "value": "utf-8",
                          "unescaped": false,
                        },
                      ],
                      "children": [],
                      "self_closing": false,
                    },
                  ],
                  [
                    "Element",
                    {
                      "tag": "title",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "Example"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
            [
              "Element",
              {
                "tag": "body",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  [
                    "Element",
                    {
                      "tag": "h1",
                      "id": "title",
                      "classes": ["heading"],
                      "attributes": [],
                      "children": [["Text", "Welcome"]],
                      "self_closing": false,
                    },
                  ],
                  [
                    "Element",
                    {
                      "tag": "p",
                      "id": "",
                      "classes": ["intro"],
                      "attributes": [],
                      "children": [["Text", "This is a paragraph."]],
                      "self_closing": false,
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "interpolation" {
  let locals = Locals::new()
  locals.set("name", "World")
  inspect(
    @pug.render_with_locals("p Hello #{name}!", locals),
    content="<p>Hello World!</p>",
  )
  json_inspect(@pug.parse("p Hello #{name}!").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            ["Text", "Hello "],
            ["Interpolation", "name"],
            ["Text", "!"],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "multiple interpolations" {
  let locals = Locals::new()
  locals.set("first", "John")
  locals.set("last", "Doe")
  inspect(
    @pug.render_with_locals("p #{first} #{last}", locals),
    content="<p>John Doe</p>",
  )
  json_inspect(@pug.parse("p #{first} #{last}").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            ["Interpolation", "first"],
            ["Text", " "],
            ["Interpolation", "last"],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "missing interpolation variable" {
  let locals = Locals::new()
  inspect(
    @pug.render_with_locals("p Hello #{name}!", locals),
    content="<p>Hello !</p>",
  )
  json_inspect(@pug.parse("p Hello #{name}!").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            ["Text", "Hello "],
            ["Interpolation", "name"],
            ["Text", "!"],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "compile and render" {
  let template = compile("p Hello #{name}!")
  let locals1 = Locals::new()
  locals1.set("name", "Alice")
  inspect(template.render(locals1), content="<p>Hello Alice!</p>")
  let locals2 = Locals::new()
  locals2.set("name", "Bob")
  inspect(template.render(locals2), content="<p>Hello Bob!</p>")
  json_inspect(@pug.parse("p Hello #{name}!").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            ["Text", "Hello "],
            ["Interpolation", "name"],
            ["Text", "!"],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "interpolation in nested elements" {
  let pug =
    #|div
    #|  p Hello #{name}
    #|  p Welcome to #{place}
  let locals = Locals::new()
  locals.set("name", "User")
  locals.set("place", "MoonBit")
  inspect(
    @pug.render_with_locals(pug, locals),
    content="<div><p>Hello User</p><p>Welcome to MoonBit</p></div>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Hello "], ["Interpolation", "name"]],
                "self_closing": false,
              },
            ],
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  ["Text", "Welcome to "],
                  ["Interpolation", "place"],
                ],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "simple include parsing" {
  // Include requires a template registry
  // For now just test parsing
  let pug =
    #|html
    #|  include header.pug
    #|  body
    #|    p Content
    #|  include footer.pug
  let doc = parse(pug)
  json_inspect(doc.node_count() > 0, content=true)
}

///|
test "include with registry" {
  let registry = TemplateRegistry::new()
  registry.register("header.pug", "header\n  h1 Site Title")
  registry.register("footer.pug", "footer\n  p Copyright 2024")
  let pug =
    #|html
    #|  include header.pug
    #|  body
    #|    p Content
    #|  include footer.pug
  inspect(
    @pug.render_with_registry(pug, Locals::new(), registry),
    content="<html><header><h1>Site Title</h1></header><body><p>Content</p></body><footer><p>Copyright 2024</p></footer></html>",
  )
  json_inspect(@pug.parse_with_registry(pug, registry).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "html",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "header",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  [
                    "Element",
                    {
                      "tag": "h1",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "Site Title"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
            [
              "Element",
              {
                "tag": "body",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  [
                    "Element",
                    {
                      "tag": "p",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "Content"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
            [
              "Element",
              {
                "tag": "footer",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  [
                    "Element",
                    {
                      "tag": "p",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "Copyright 2024"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "include not found" {
  let registry = TemplateRegistry::new()
  let pug =
    #|html
    #|  include missing.pug
  inspect(
    @pug.render_with_registry(pug, Locals::new(), registry),
    content="<html><!-- Include not found: missing.pug --></html>",
  )
  json_inspect(@pug.parse_with_registry(pug, registry).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "html",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Comment",
              { "text": "Include not found: missing.pug", "render": true },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "include with locals" {
  let registry = TemplateRegistry::new()
  registry.register("greeting.pug", "p Hello #{name}")
  let pug =
    #|div
    #|  include greeting.pug
  let locals = Locals::new()
  locals.set("name", "World")
  inspect(
    @pug.render_with_registry(pug, locals, registry),
    content="<div><p>Hello World</p></div>",
  )
  json_inspect(@pug.parse_with_registry(pug, registry).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Hello "], ["Interpolation", "name"]],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
/// Test rendering example_priv_test/index.pug with includes
/// This should produce the same output as the official Pug library
/// Compare with: node example_test.js
test "include example - simple API" {
  // Just like pug.renderFile() in JavaScript!
  // Expected output from official Pug: node example_test.js
  inspect(
    @pug.render_file("example_priv_test/index.pug"),
    content="<!DOCTYPE html><html><head><title>My Site</title><script src=\"/javascripts/jquery.js\"></script><script src=\"/javascripts/app.js\"></script></head><body><h1>My Site</h1><p>Welcome to my super lame site.</p><footer id=\"footer\"><p>Copyright (c) foobar</p></footer></body></html>",
  )
}

///|
test "simple filter parsing" {
  let pug =
    #|:plain
    #|  This is plain text
    #|  that spans multiple lines
  let doc = parse(pug)
  json_inspect(doc.node_count() > 0, content=true)
}

///|
test "attribute with single quotes" {
  inspect(
    @pug.render("a(href='https://example.com') Link"),
    content="<a href=\"https://example.com\">Link</a>",
  )
  json_inspect(
    @pug.parse("a(href='https://example.com') Link").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "a",
            "id": "",
            "classes": [],
            "attributes": [
              {
                "name": "href",
                "value": "https://example.com",
                "unescaped": false,
              },
            ],
            "children": [["Text", "Link"]],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "multi-line attributes" {
  let pug =
    #|input(
    #|  type="checkbox"
    #|  name="agreement"
    #|  checked
    #|)
  inspect(
    @pug.render(pug),
    content="<input type=\"checkbox\" name=\"agreement\" checked>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "input",
          "id": "",
          "classes": [],
          "attributes": [
            { "name": "type", "value": "checkbox", "unescaped": false },
            { "name": "name", "value": "agreement", "unescaped": false },
            { "name": "checked", "unescaped": false },
          ],
          "children": [],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "boolean attribute" {
  inspect(
    @pug.render("input(type=\"checkbox\", checked)"),
    content="<input type=\"checkbox\" checked>",
  )
  json_inspect(@pug.parse("input(type=\"checkbox\", checked)").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "input",
          "id": "",
          "classes": [],
          "attributes": [
            { "name": "type", "value": "checkbox", "unescaped": false },
            { "name": "checked", "unescaped": false },
          ],
          "children": [],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "boolean attribute standalone" {
  inspect(@pug.render("input(disabled)"), content="<input disabled>")
  json_inspect(@pug.parse("input(disabled)").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "input",
          "id": "",
          "classes": [],
          "attributes": [{ "name": "disabled", "unescaped": false }],
          "children": [],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "multiple boolean attributes" {
  inspect(
    @pug.render("input(type=\"text\", required, readonly)"),
    content="<input type=\"text\" required readonly>",
  )
  json_inspect(
    @pug.parse("input(type=\"text\", required, readonly)").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "input",
            "id": "",
            "classes": [],
            "attributes": [
              { "name": "type", "value": "text", "unescaped": false },
              { "name": "required", "unescaped": false },
              { "name": "readonly", "unescaped": false },
            ],
            "children": [],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "unescaped attribute with !=" {
  inspect(
    @pug.render("div(data-content!=\"<strong>bold</strong>\")"),
    content="<div data-content=\"<strong>bold</strong>\"></div>",
  )
  json_inspect(
    @pug.parse("div(data-content!=\"<strong>bold</strong>\")").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "div",
            "id": "",
            "classes": [],
            "attributes": [
              {
                "name": "data-content",
                "value": "<strong>bold</strong>",
                "unescaped": true,
              },
            ],
            "children": [],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "escaped attribute value" {
  inspect(
    @pug.render("div(data-content=\"<script>alert('xss')</script>\")"),
    content="<div data-content=\"&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;\"></div>",
  )
  json_inspect(
    @pug.parse("div(data-content=\"<script>alert('xss')</script>\")").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "div",
            "id": "",
            "classes": [],
            "attributes": [
              {
                "name": "data-content",
                "value": "<script>alert('xss')</script>",
                "unescaped": false,
              },
            ],
            "children": [],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "attribute with interpolation" {
  let locals = Locals::new()
  locals.set("url", "https://moonbit.io")
  inspect(
    @pug.render_with_locals("a(href=\"#{url}\") MoonBit", locals),
    content="<a href=\"https://moonbit.io\">MoonBit</a>",
  )
  json_inspect(@pug.parse("a(href=\"#{url}\") MoonBit").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "a",
          "id": "",
          "classes": [],
          "attributes": [
            { "name": "href", "value": "#{url}", "unescaped": false },
          ],
          "children": [["Text", "MoonBit"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "class and id combined with attributes" {
  inspect(
    @pug.render("button#submit.btn.primary(type=\"submit\") Submit"),
    content="<button id=\"submit\" class=\"btn primary\" type=\"submit\">Submit</button>",
  )
  json_inspect(
    @pug.parse("button#submit.btn.primary(type=\"submit\") Submit").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "button",
            "id": "submit",
            "classes": ["btn", "primary"],
            "attributes": [
              { "name": "type", "value": "submit", "unescaped": false },
            ],
            "children": [["Text", "Submit"]],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "empty attribute value" {
  inspect(
    @pug.render("div(data-empty=\"\")"),
    content="<div data-empty=\"\"></div>",
  )
  json_inspect(@pug.parse("div(data-empty=\"\")").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": [],
          "attributes": [
            { "name": "data-empty", "value": "", "unescaped": false },
          ],
          "children": [],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "attribute with spaces in value" {
  inspect(
    @pug.render("div(title=\"Hello World\")"),
    content="<div title=\"Hello World\"></div>",
  )
  json_inspect(@pug.parse("div(title=\"Hello World\")").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": [],
          "attributes": [
            { "name": "title", "value": "Hello World", "unescaped": false },
          ],
          "children": [],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "data attributes" {
  inspect(
    @pug.render("div(data-id=\"123\", data-name=\"test\")"),
    content="<div data-id=\"123\" data-name=\"test\"></div>",
  )
  json_inspect(
    @pug.parse("div(data-id=\"123\", data-name=\"test\")").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "div",
            "id": "",
            "classes": [],
            "attributes": [
              { "name": "data-id", "value": "123", "unescaped": false },
              { "name": "data-name", "value": "test", "unescaped": false },
            ],
            "children": [],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "simple block expansion" {
  inspect(@pug.render("a: img"), content="<a><img></a>")
  json_inspect(@pug.parse("a: img").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "a",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "img",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "block expansion with text" {
  inspect(
    @pug.render("p: strong Bold text"),
    content="<p><strong>Bold text</strong></p>",
  )
  json_inspect(@pug.parse("p: strong Bold text").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "strong",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Bold text"]],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "block expansion with attributes" {
  inspect(
    @pug.render("a(href=\"/\"): img(src=\"logo.png\")"),
    content="<a href=\"/\"><img src=\"logo.png\"></a>",
  )
  json_inspect(
    @pug.parse("a(href=\"/\"): img(src=\"logo.png\")").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "a",
            "id": "",
            "classes": [],
            "attributes": [{ "name": "href", "value": "/", "unescaped": false }],
            "children": [
              [
                "Element",
                {
                  "tag": "img",
                  "id": "",
                  "classes": [],
                  "attributes": [
                    { "name": "src", "value": "logo.png", "unescaped": false },
                  ],
                  "children": [],
                  "self_closing": false,
                },
              ],
            ],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "chained block expansion" {
  inspect(
    @pug.render("div: p: span Hello"),
    content="<div><p><span>Hello</span></p></div>",
  )
  json_inspect(@pug.parse("div: p: span Hello").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  [
                    "Element",
                    {
                      "tag": "span",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "Hello"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "block expansion with class" {
  inspect(
    @pug.render("ul.menu: li.item First"),
    content="<ul class=\"menu\"><li class=\"item\">First</li></ul>",
  )
  json_inspect(@pug.parse("ul.menu: li.item First").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "ul",
          "id": "",
          "classes": ["menu"],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "li",
                "id": "",
                "classes": ["item"],
                "attributes": [],
                "children": [["Text", "First"]],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "block expansion followed by sibling" {
  let pug =
    #|div
    #|  p: span Inline
    #|  p Normal
  inspect(
    @pug.render(pug),
    content="<div><p><span>Inline</span></p><p>Normal</p></div>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  [
                    "Element",
                    {
                      "tag": "span",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "Inline"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Normal"]],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "case with when" {
  let pug =
    #|case status
    #|  when "active"
    #|    p Active
    #|  when "pending"
    #|    p Pending
    #|  default
    #|    p Unknown
  let locals = Locals::new()
  locals.set("status", "active")
  inspect(@pug.render_with_locals(pug, locals), content="<p>Active</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Case",
        {
          "expr": "status",
          "cases": [
            [
              "active",
              [
                [
                  "Element",
                  {
                    "tag": "p",
                    "id": "",
                    "classes": [],
                    "attributes": [],
                    "children": [["Text", "Active"]],
                    "self_closing": false,
                  },
                ],
              ],
            ],
            [
              "pending",
              [
                [
                  "Element",
                  {
                    "tag": "p",
                    "id": "",
                    "classes": [],
                    "attributes": [],
                    "children": [["Text", "Pending"]],
                    "self_closing": false,
                  },
                ],
              ],
            ],
          ],
          "default": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Unknown"]],
                "self_closing": false,
              },
            ],
          ],
        },
      ],
    ],
  })
}

///|
test "case with default" {
  let pug =
    #|case status
    #|  when "active"
    #|    p Active
    #|  default
    #|    p Unknown
  let locals = Locals::new()
  locals.set("status", "other")
  inspect(@pug.render_with_locals(pug, locals), content="<p>Unknown</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Case",
        {
          "expr": "status",
          "cases": [
            [
              "active",
              [
                [
                  "Element",
                  {
                    "tag": "p",
                    "id": "",
                    "classes": [],
                    "attributes": [],
                    "children": [["Text", "Active"]],
                    "self_closing": false,
                  },
                ],
              ],
            ],
          ],
          "default": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Unknown"]],
                "self_closing": false,
              },
            ],
          ],
        },
      ],
    ],
  })
}

///|
test "case with fall through" {
  let pug =
    #|case num
    #|  when 0
    #|  when 1
    #|  when 2
    #|    p Small number
    #|  default
    #|    p Large number
  let locals = Locals::new()
  locals.set("num", "1")
  inspect(@pug.render_with_locals(pug, locals), content="<p>Small number</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Case",
        {
          "expr": "num",
          "cases": [
            ["0", []],
            ["1", []],
            [
              "2",
              [
                [
                  "Element",
                  {
                    "tag": "p",
                    "id": "",
                    "classes": [],
                    "attributes": [],
                    "children": [["Text", "Small number"]],
                    "self_closing": false,
                  },
                ],
              ],
            ],
          ],
          "default": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Large number"]],
                "self_closing": false,
              },
            ],
          ],
        },
      ],
    ],
  })
}

///|
test "case with block expansion" {
  let pug =
    #|case type
    #|  when "a": p Type A
    #|  when "b": p Type B
    #|  default: p Other
  let locals = Locals::new()
  locals.set("type", "b")
  inspect(@pug.render_with_locals(pug, locals), content="<p>Type B</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Case",
        {
          "expr": "type",
          "cases": [
            [
              "a",
              [
                [
                  "Element",
                  {
                    "tag": "p",
                    "id": "",
                    "classes": [],
                    "attributes": [],
                    "children": [["Text", "Type A"]],
                    "self_closing": false,
                  },
                ],
              ],
            ],
            [
              "b",
              [
                [
                  "Element",
                  {
                    "tag": "p",
                    "id": "",
                    "classes": [],
                    "attributes": [],
                    "children": [["Text", "Type B"]],
                    "self_closing": false,
                  },
                ],
              ],
            ],
          ],
          "default": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Other"]],
                "self_closing": false,
              },
            ],
          ],
        },
      ],
    ],
  })
}

///|
test "nested case" {
  let pug =
    #|div
    #|  case color
    #|    when "red"
    #|      span.red Red
    #|    when "blue"
    #|      span.blue Blue
  let locals = Locals::new()
  locals.set("color", "red")
  inspect(
    @pug.render_with_locals(pug, locals),
    content="<div><span class=\"red\">Red</span></div>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Case",
              {
                "expr": "color",
                "cases": [
                  [
                    "red",
                    [
                      [
                        "Element",
                        {
                          "tag": "span",
                          "id": "",
                          "classes": ["red"],
                          "attributes": [],
                          "children": [["Text", "Red"]],
                          "self_closing": false,
                        },
                      ],
                    ],
                  ],
                  [
                    "blue",
                    [
                      [
                        "Element",
                        {
                          "tag": "span",
                          "id": "",
                          "classes": ["blue"],
                          "attributes": [],
                          "children": [["Text", "Blue"]],
                          "self_closing": false,
                        },
                      ],
                    ],
                  ],
                ],
                "default": [],
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "unbuffered code variable" {
  let pug =
    #|- var greeting = "Hello"
    #|p= greeting
  inspect(@pug.render(pug), content="<p>Hello</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      ["VarAssign", { "name": "", "value": "var greeting = \"Hello\"" }],
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [["Interpolation", "greeting"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "buffered code output" {
  let pug =
    #|p= message
  let locals = Locals::new()
  locals.set("message", "Hello World")
  inspect(@pug.render_with_locals(pug, locals), content="<p>Hello World</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [["Interpolation", "message"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "buffered code escapes html" {
  let pug =
    #|p= content
  let locals = Locals::new()
  locals.set("content", "<script>alert('xss')</script>")
  inspect(
    @pug.render_with_locals(pug, locals),
    content="<p>&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;</p>",
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
          "children": [["Interpolation", "content"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "unescaped buffered code" {
  let pug =
    #|p!= content
  let locals = Locals::new()
  locals.set("content", "<strong>bold</strong>")
  inspect(
    @pug.render_with_locals(pug, locals),
    content="<p><strong>bold</strong></p>",
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
          "children": [["UnescapedInterpolation", "content"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "inline buffered code" {
  let pug =
    #|p The answer is #{answer}
  let locals = Locals::new()
  locals.set("answer", "42")
  inspect(
    @pug.render_with_locals(pug, locals),
    content="<p>The answer is 42</p>",
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
          "children": [["Text", "The answer is "], ["Interpolation", "answer"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "code with conditional" {
  let pug =
    #|- var show = true
    #|if show
    #|  p Visible
  inspect(@pug.render(pug), content="<p>Visible</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      ["VarAssign", { "name": "", "value": "var show = true" }],
      [
        "Conditional",
        {
          "condition": "show",
          "if_true": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Visible"]],
                "self_closing": false,
              },
            ],
          ],
          "if_false": [],
          "is_unless": false,
        },
      ],
    ],
  })
}

///|
test "code defining list" {
  let pug =
    #|- var list = ["a", "b", "c"]
    #|ul
    #|  each item in list
    #|    li= item
  inspect(@pug.render(pug), content="<ul><li>a</li><li>b</li><li>c</li></ul>")
}

///|
test "buffered comment" {
  inspect(
    @pug.render("// This appears in HTML"),
    content="<!--This appears in HTML-->",
  )
  json_inspect(@pug.parse("// This appears in HTML").to_test_json(), content={
    "nodes": [["Comment", { "text": "This appears in HTML", "render": true }]],
  })
}

///|
test "unbuffered comment" {
  inspect(@pug.render("//- This is hidden"), content="")
  json_inspect(@pug.parse("//- This is hidden").to_test_json(), content={
    "nodes": [],
  })
}

///|
test "comment with content below" {
  let pug =
    #|// visible comment
    #|p Hello
  inspect(@pug.render(pug), content="<!--visible comment--><p>Hello</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      ["Comment", { "text": "visible comment", "render": true }],
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [["Text", "Hello"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "unbuffered comment with content below" {
  let pug =
    #|//- hidden comment
    #|p Hello
  inspect(@pug.render(pug), content="<p>Hello</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [["Text", "Hello"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "block comment buffered" {
  let pug =
    #|//
    #|  This is a
    #|  multi-line comment
  inspect(@pug.render(pug), content="<!--This is a\nmulti-line comment-->")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      ["Comment", { "text": "This is a\nmulti-line comment", "render": true }],
    ],
  })
}

///|
test "block comment unbuffered" {
  let pug =
    #|//-
    #|  This comment
    #|  is hidden
    #|p Visible
  inspect(@pug.render(pug), content="<p>Visible</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [["Text", "Visible"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "comment in nested structure" {
  let pug =
    #|div
    #|  // comment inside
    #|  p Content
  inspect(
    @pug.render(pug),
    content="<div><!--comment inside--><p>Content</p></div>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "div",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            ["Comment", { "text": "comment inside", "render": true }],
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Content"]],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "if true condition" {
  let pug =
    #|if show
    #|  p Visible
  let locals = Locals::new()
  locals.set("show", "true")
  inspect(@pug.render_with_locals(pug, locals), content="<p>Visible</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Conditional",
        {
          "condition": "show",
          "if_true": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Visible"]],
                "self_closing": false,
              },
            ],
          ],
          "if_false": [],
          "is_unless": false,
        },
      ],
    ],
  })
}

///|
test "if false condition" {
  let pug =
    #|if show
    #|  p Visible
  let locals = Locals::new()
  locals.set("show", "false")
  inspect(@pug.render_with_locals(pug, locals), content="")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Conditional",
        {
          "condition": "show",
          "if_true": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Visible"]],
                "self_closing": false,
              },
            ],
          ],
          "if_false": [],
          "is_unless": false,
        },
      ],
    ],
  })
}

///|
test "if-else" {
  let pug =
    #|if loggedIn
    #|  p Welcome back
    #|else
    #|  p Please log in
  let locals = Locals::new()
  locals.set("loggedIn", "false")
  inspect(@pug.render_with_locals(pug, locals), content="<p>Please log in</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Conditional",
        {
          "condition": "loggedIn",
          "if_true": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Welcome back"]],
                "self_closing": false,
              },
            ],
          ],
          "if_false": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Please log in"]],
                "self_closing": false,
              },
            ],
          ],
          "is_unless": false,
        },
      ],
    ],
  })
}

///|
test "if-else if-else" {
  let pug =
    #|if status == "active"
    #|  p.green Active
    #|else if status == "pending"
    #|  p.yellow Pending
    #|else
    #|  p.red Inactive
  let locals = Locals::new()
  locals.set("status", "pending")
  inspect(
    @pug.render_with_locals(pug, locals),
    content="<p class=\"yellow\">Pending</p>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Conditional",
        {
          "condition": "status == \"active\"",
          "if_true": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": ["green"],
                "attributes": [],
                "children": [["Text", "Active"]],
                "self_closing": false,
              },
            ],
          ],
          "if_false": [],
          "is_unless": false,
        },
      ],
      [
        "Conditional",
        {
          "condition": "status == \"pending\"",
          "if_true": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": ["yellow"],
                "attributes": [],
                "children": [["Text", "Pending"]],
                "self_closing": false,
              },
            ],
          ],
          "if_false": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": ["red"],
                "attributes": [],
                "children": [["Text", "Inactive"]],
                "self_closing": false,
              },
            ],
          ],
          "is_unless": false,
        },
      ],
    ],
  })
}

///|
test "unless true" {
  let pug =
    #|unless hidden
    #|  p Shown
  let locals = Locals::new()
  locals.set("hidden", "true")
  inspect(@pug.render_with_locals(pug, locals), content="")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Conditional",
        {
          "condition": "hidden",
          "if_true": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Shown"]],
                "self_closing": false,
              },
            ],
          ],
          "if_false": [],
          "is_unless": true,
        },
      ],
    ],
  })
}

///|
test "unless false" {
  let pug =
    #|unless hidden
    #|  p Shown
  let locals = Locals::new()
  locals.set("hidden", "false")
  inspect(@pug.render_with_locals(pug, locals), content="<p>Shown</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Conditional",
        {
          "condition": "hidden",
          "if_true": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Shown"]],
                "self_closing": false,
              },
            ],
          ],
          "if_false": [],
          "is_unless": true,
        },
      ],
    ],
  })
}

///|
test "nested conditionals" {
  let pug =
    #|if user
    #|  if user.admin
    #|    p Admin Panel
    #|  else
    #|    p User Dashboard
  let locals = Locals::new()
  locals.set("user", "true")
  locals.set("user.admin", "true")
  inspect(@pug.render_with_locals(pug, locals), content="<p>Admin Panel</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Conditional",
        {
          "condition": "user",
          "if_true": [
            [
              "Conditional",
              {
                "condition": "user.admin",
                "if_true": [
                  [
                    "Element",
                    {
                      "tag": "p",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "Admin Panel"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "if_false": [
                  [
                    "Element",
                    {
                      "tag": "p",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "User Dashboard"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "is_unless": false,
              },
            ],
          ],
          "if_false": [],
          "is_unless": false,
        },
      ],
    ],
  })
}

///|
test "conditional with variable check" {
  let pug =
    #|if name
    #|  p Hello #{name}
    #|else
    #|  p Hello Guest
  let locals = Locals::new()
  locals.set("name", "Alice")
  inspect(@pug.render_with_locals(pug, locals), content="<p>Hello Alice</p>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Conditional",
        {
          "condition": "name",
          "if_true": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Hello "], ["Interpolation", "name"]],
                "self_closing": false,
              },
            ],
          ],
          "if_false": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "Hello Guest"]],
                "self_closing": false,
              },
            ],
          ],
          "is_unless": false,
        },
      ],
    ],
  })
}

///|
test "simple block definition" {
  let pug =
    #|html
    #|  body
    #|    block content
    #|      p Default content
  inspect(
    @pug.render(pug),
    content="<html><body><p>Default content</p></body></html>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "html",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "body",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  [
                    "NamedBlock",
                    {
                      "name": "content",
                      "body": [
                        [
                          "Element",
                          {
                            "tag": "p",
                            "id": "",
                            "classes": [],
                            "attributes": [],
                            "children": [["Text", "Default content"]],
                            "self_closing": false,
                          },
                        ],
                      ],
                      "mode": "replace",
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "block with extends" {
  // This requires a template registry approach
  // For now, test the parsing
  let layout =
    #|html
    #|  head
    #|    block head
    #|      title Default Title
    #|  body
    #|    block content
  let child =
    #|extends layout
    #|block content
    #|  p Child content
  // Test that we can parse both templates
  let layout_doc = parse(layout)
  let child_doc = parse(child)
  json_inspect(layout_doc.node_count() > 0, content=true)
  json_inspect(child_doc.node_count() > 0, content=true)
}

///|
test "append block" {
  let pug =
    #|html
    #|  head
    #|    block scripts
    #|      script(src="/jquery.js")
    #|append scripts
    #|  script(src="/app.js")
  let html = render(pug)
  // append adds to the end of the block
  json_inspect(
    html,
    content="<html><head><script src=\"/jquery.js\"></script><script src=\"/app.js\"></script></head></html>",
  )
}

///|
test "prepend block" {
  let pug =
    #|html
    #|  head
    #|    block scripts
    #|      script(src="/app.js")
    #|prepend scripts
    #|  script(src="/jquery.js")
  let html = render(pug)
  // prepend adds to the beginning of the block
  json_inspect(
    html,
    content="<html><head><script src=\"/jquery.js\"></script><script src=\"/app.js\"></script></head></html>",
  )
}

///|
test "extends with registry - basic" {
  let registry = TemplateRegistry::new()
  // Register the layout template
  let layout =
    #|html
    #|  head
    #|    block head
    #|      title Default Title
    #|  body
    #|    block content
    #|      p Default content
  registry.register("layout.pug", layout)
  // Child template that extends layout
  let child =
    #|extends layout.pug
    #|block content
    #|  p Child content
  let html = render_with_registry(child, Locals::new(), registry)
  json_inspect(
    html,
    content="<html><head><title>Default Title</title></head><body><p>Child content</p></body></html>",
  )
}

///|
test "extends with registry - append block" {
  let registry = TemplateRegistry::new()
  let layout =
    #|html
    #|  head
    #|    block scripts
    #|      script(src="/jquery.js")
  registry.register("layout.pug", layout)
  let child =
    #|extends layout.pug
    #|append scripts
    #|  script(src="/app.js")
  let html = render_with_registry(child, Locals::new(), registry)
  json_inspect(
    html,
    content="<html><head><script src=\"/jquery.js\"></script><script src=\"/app.js\"></script></head></html>",
  )
}

///|
test "extends with registry - prepend block" {
  let registry = TemplateRegistry::new()
  let layout =
    #|html
    #|  head
    #|    block scripts
    #|      script(src="/app.js")
  registry.register("layout.pug", layout)
  let child =
    #|extends layout.pug
    #|prepend scripts
    #|  script(src="/jquery.js")
  let html = render_with_registry(child, Locals::new(), registry)
  json_inspect(
    html,
    content="<html><head><script src=\"/jquery.js\"></script><script src=\"/app.js\"></script></head></html>",
  )
}

///|
test "escaped interpolation" {
  let locals = Locals::new()
  locals.set("content", "<script>alert('xss')</script>")
  inspect(
    @pug.render_with_locals("p #{content}", locals),
    content="<p>&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;</p>",
  )
  json_inspect(@pug.parse("p #{content}").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [["Interpolation", "content"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "unescaped interpolation with !{}" {
  let locals = Locals::new()
  locals.set("content", "<strong>bold</strong>")
  inspect(
    @pug.render_with_locals("p !{content}", locals),
    content="<p><strong>bold</strong></p>",
  )
  json_inspect(@pug.parse("p !{content}").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [["UnescapedInterpolation", "content"]],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "mixed escaped and unescaped" {
  let locals = Locals::new()
  locals.set("safe", "Hello")
  locals.set("html", "<em>World</em>")
  inspect(
    @pug.render_with_locals("p #{safe} !{html}", locals),
    content="<p>Hello <em>World</em></p>",
  )
  json_inspect(@pug.parse("p #{safe} !{html}").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            ["Interpolation", "safe"],
            ["Text", " "],
            ["UnescapedInterpolation", "html"],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "tag interpolation with #[]" {
  inspect(
    @pug.render("p This is #[strong important] text"),
    content="<p>This is <strong>important</strong> text</p>",
  )
  json_inspect(
    @pug.parse("p This is #[strong important] text").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "p",
            "id": "",
            "classes": [],
            "attributes": [],
            "children": [
              ["Text", "This is "],
              [
                "Element",
                {
                  "tag": "strong",
                  "id": "",
                  "classes": [],
                  "attributes": [],
                  "children": [["Text", "important"]],
                  "self_closing": false,
                },
              ],
              ["Text", " text"],
            ],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "tag interpolation with attributes" {
  inspect(
    @pug.render("p Click #[a(href=\"/\") here] to continue"),
    content="<p>Click <a href=\"/\">here</a> to continue</p>",
  )
  json_inspect(
    @pug.parse("p Click #[a(href=\"/\") here] to continue").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "p",
            "id": "",
            "classes": [],
            "attributes": [],
            "children": [
              ["Text", "Click "],
              [
                "Element",
                {
                  "tag": "a",
                  "id": "",
                  "classes": [],
                  "attributes": [
                    { "name": "href", "value": "/", "unescaped": false },
                  ],
                  "children": [["Text", "here"]],
                  "self_closing": false,
                },
              ],
              ["Text", " to continue"],
            ],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "nested tag interpolation" {
  inspect(
    @pug.render("p #[strong #[em nested]] content"),
    content="<p><strong><em>nested</em></strong> content</p>",
  )
  json_inspect(@pug.parse("p #[strong #[em nested]] content").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Element",
              {
                "tag": "strong",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  [
                    "Element",
                    {
                      "tag": "em",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "nested"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
            ["Text", " content"],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "interpolation in attribute" {
  let locals = Locals::new()
  locals.set("id", "main")
  locals.set("cls", "active")
  inspect(
    @pug.render_with_locals("div(id=\"#{id}\", class=\"#{cls}\")", locals),
    content="<div id=\"main\" class=\"active\"></div>",
  )
  json_inspect(
    @pug.parse("div(id=\"#{id}\", class=\"#{cls}\")").to_test_json(),
    content={
      "nodes": [
        [
          "Element",
          {
            "tag": "div",
            "id": "",
            "classes": [],
            "attributes": [
              { "name": "id", "value": "#{id}", "unescaped": false },
              { "name": "class", "value": "#{cls}", "unescaped": false },
            ],
            "children": [],
            "self_closing": false,
          },
        ],
      ],
    },
  )
}

///|
test "interpolation with method call syntax" {
  // In our implementation, we just look up the variable name
  let locals = Locals::new()
  locals.set("name", "moonbit")
  inspect(
    @pug.render_with_locals("p Welcome to #{name}!", locals),
    content="<p>Welcome to moonbit!</p>",
  )
  json_inspect(@pug.parse("p Welcome to #{name}!").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            ["Text", "Welcome to "],
            ["Interpolation", "name"],
            ["Text", "!"],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "whitespace around interpolation" {
  let locals = Locals::new()
  locals.set("name", "World")
  inspect(
    @pug.render_with_locals("p Hello #{name} !", locals),
    content="<p>Hello World !</p>",
  )
  json_inspect(@pug.parse("p Hello #{name} !").to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "p",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            ["Text", "Hello "],
            ["Interpolation", "name"],
            ["Text", " !"],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "each over array" {
  let pug =
    #|ul
    #|  each item in items
    #|    li #{item}
  let locals = Locals::new()
  locals.set_array("items", ["Apple", "Banana", "Cherry"])
  inspect(
    @pug.render_with_locals(pug, locals),
    content="<ul><li>Apple</li><li>Banana</li><li>Cherry</li></ul>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "ul",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Each",
              {
                "item_var": "item",
                "index_var": "",
                "collection": "items",
                "body": [
                  [
                    "Element",
                    {
                      "tag": "li",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Interpolation", "item"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "else_body": [],
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "each with index" {
  let pug =
    #|ul
    #|  each item, index in items
    #|    li #{index}: #{item}
  let locals = Locals::new()
  locals.set_array("items", ["a", "b", "c"])
  inspect(
    @pug.render_with_locals(pug, locals),
    content="<ul><li>0: a</li><li>1: b</li><li>2: c</li></ul>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "ul",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Each",
              {
                "item_var": "item",
                "index_var": "index",
                "collection": "items",
                "body": [
                  [
                    "Element",
                    {
                      "tag": "li",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [
                        ["Interpolation", "index"],
                        ["Text", ": "],
                        ["Interpolation", "item"],
                      ],
                      "self_closing": false,
                    },
                  ],
                ],
                "else_body": [],
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "each over object" {
  let pug =
    #|ul
    #|  each val, key in obj
    #|    li #{key}: #{val}
  let locals = Locals::new()
  locals.set_object("obj", { "name": "Alice", "age": "30" })
  inspect(
    @pug.render_with_locals(pug, locals),
    content="<ul><li>name: Alice</li><li>age: 30</li></ul>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "ul",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Each",
              {
                "item_var": "val",
                "index_var": "key",
                "collection": "obj",
                "body": [
                  [
                    "Element",
                    {
                      "tag": "li",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [
                        ["Interpolation", "key"],
                        ["Text", ": "],
                        ["Interpolation", "val"],
                      ],
                      "self_closing": false,
                    },
                  ],
                ],
                "else_body": [],
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "each with else for empty" {
  let pug =
    #|ul
    #|  each item in items
    #|    li #{item}
    #|  else
    #|    li No items
  let locals = Locals::new()
  locals.set_array("items", [])
  inspect(
    @pug.render_with_locals(pug, locals),
    content="<ul><li>No items</li></ul>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "ul",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Each",
              {
                "item_var": "item",
                "index_var": "",
                "collection": "items",
                "body": [
                  [
                    "Element",
                    {
                      "tag": "li",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Interpolation", "item"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "else_body": [
                  [
                    "Element",
                    {
                      "tag": "li",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "No items"]],
                      "self_closing": false,
                    },
                  ],
                ],
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "for alias for each" {
  let pug =
    #|ul
    #|  for item in items
    #|    li #{item}
  let locals = Locals::new()
  locals.set_array("items", ["One", "Two"])
  inspect(
    @pug.render_with_locals(pug, locals),
    content="<ul><li>One</li><li>Two</li></ul>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "ul",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Each",
              {
                "item_var": "item",
                "index_var": "",
                "collection": "items",
                "body": [
                  [
                    "Element",
                    {
                      "tag": "li",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Interpolation", "item"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "else_body": [],
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "while loop" {
  let pug =
    #|ul
    #|  - var n = 0
    #|  while n < 3
    #|    li= n++
  inspect(@pug.render(pug), content="<ul><li>0</li><li>1</li><li>2</li></ul>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "ul",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            ["VarAssign", { "name": "", "value": "var n = 0" }],
            [
              "While",
              {
                "condition": "n < 3",
                "body": [
                  [
                    "Element",
                    {
                      "tag": "li",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Interpolation", "n++"]],
                      "self_closing": false,
                    },
                  ],
                ],
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "nested iteration" {
  let pug =
    #|table
    #|  each row in rows
    #|    tr
    #|      each cell in row
    #|        td #{cell}
  let locals = Locals::new()
  locals.set_nested_array("rows", [["1", "2"], ["3", "4"]])
  inspect(
    @pug.render_with_locals(pug, locals),
    content="<table><tr><td>1</td><td>2</td></tr><tr><td>3</td><td>4</td></tr></table>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "Element",
        {
          "tag": "table",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "Each",
              {
                "item_var": "row",
                "index_var": "",
                "collection": "rows",
                "body": [
                  [
                    "Element",
                    {
                      "tag": "tr",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [
                        [
                          "Each",
                          {
                            "item_var": "cell",
                            "index_var": "",
                            "collection": "row",
                            "body": [
                              [
                                "Element",
                                {
                                  "tag": "td",
                                  "id": "",
                                  "classes": [],
                                  "attributes": [],
                                  "children": [["Interpolation", "cell"]],
                                  "self_closing": false,
                                },
                              ],
                            ],
                            "else_body": [],
                          },
                        ],
                      ],
                      "self_closing": false,
                    },
                  ],
                ],
                "else_body": [],
              },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "simple mixin definition and call" {
  let pug =
    #|mixin list
    #|  ul
    #|    li foo
    #|    li bar
    #|+list
  inspect(@pug.render(pug), content="<ul><li>foo</li><li>bar</li></ul>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "MixinDef",
        {
          "name": "list",
          "params": [],
          "body": [
            [
              "Element",
              {
                "tag": "ul",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [
                  [
                    "Element",
                    {
                      "tag": "li",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "foo"]],
                      "self_closing": false,
                    },
                  ],
                  [
                    "Element",
                    {
                      "tag": "li",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Text", "bar"]],
                      "self_closing": false,
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
          ],
        },
      ],
      ["MixinCall", { "name": "list", "args": [], "block": [], "attrs": [] }],
    ],
  })
}

///|
test "mixin with argument" {
  let pug =
    #|mixin pet(name)
    #|  li.pet= name
    #|ul
    #|  +pet("cat")
    #|  +pet("dog")
  inspect(
    @pug.render(pug),
    content="<ul><li class=\"pet\">cat</li><li class=\"pet\">dog</li></ul>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "MixinDef",
        {
          "name": "pet",
          "params": [["name", ""]],
          "body": [
            [
              "Element",
              {
                "tag": "li",
                "id": "",
                "classes": ["pet"],
                "attributes": [],
                "children": [["Interpolation", "name"]],
                "self_closing": false,
              },
            ],
          ],
        },
      ],
      [
        "Element",
        {
          "tag": "ul",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "MixinCall",
              { "name": "pet", "args": ["cat"], "block": [], "attrs": [] },
            ],
            [
              "MixinCall",
              { "name": "pet", "args": ["dog"], "block": [], "attrs": [] },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "mixin with multiple arguments" {
  let pug =
    #|mixin link(href, text)
    #|  a(href=href)= text
    #|+link("/home", "Home")
    #|+link("/about", "About")
  inspect(
    @pug.render(pug),
    content="<a href=\"/home\">Home</a><a href=\"/about\">About</a>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "MixinDef",
        {
          "name": "link",
          "params": [["href", ""], ["text", ""]],
          "body": [
            [
              "Element",
              {
                "tag": "a",
                "id": "",
                "classes": [],
                "attributes": [
                  { "name": "href", "value": "href", "unescaped": false },
                ],
                "children": [["Interpolation", "text"]],
                "self_closing": false,
              },
            ],
          ],
        },
      ],
      [
        "MixinCall",
        { "name": "link", "args": ["/home", "Home"], "block": [], "attrs": [] },
      ],
      [
        "MixinCall",
        {
          "name": "link",
          "args": ["/about", "About"],
          "block": [],
          "attrs": [],
        },
      ],
    ],
  })
}

///|
test "mixin with block" {
  let pug =
    #|mixin article(title)
    #|  .article
    #|    h1= title
    #|    if block
    #|      block
    #|+article("Hello")
    #|  p This is the content
  inspect(
    @pug.render(pug),
    content="<div class=\"article\"><h1>Hello</h1><p>This is the content</p></div>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "MixinDef",
        {
          "name": "article",
          "params": [["title", ""]],
          "body": [
            [
              "Element",
              {
                "tag": "div",
                "id": "",
                "classes": ["article"],
                "attributes": [],
                "children": [
                  [
                    "Element",
                    {
                      "tag": "h1",
                      "id": "",
                      "classes": [],
                      "attributes": [],
                      "children": [["Interpolation", "title"]],
                      "self_closing": false,
                    },
                  ],
                  [
                    "Conditional",
                    {
                      "condition": "block",
                      "if_true": ["Block"],
                      "if_false": [],
                      "is_unless": false,
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
          ],
        },
      ],
      [
        "MixinCall",
        {
          "name": "article",
          "args": ["Hello"],
          "block": [
            [
              "Element",
              {
                "tag": "p",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Text", "This is the content"]],
                "self_closing": false,
              },
            ],
          ],
          "attrs": [],
        },
      ],
    ],
  })
}

///|
test "mixin with attributes" {
  let pug =
    #|mixin link(href, name)
    #|  a(class!=attributes.class, href=href)= name
    #|+link("/foo", "foo")(class="btn")
  inspect(@pug.render(pug), content="<a class=\"btn\" href=\"/foo\">foo</a>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "MixinDef",
        {
          "name": "link",
          "params": [["href", ""], ["name", ""]],
          "body": [
            [
              "Element",
              {
                "tag": "a",
                "id": "",
                "classes": [],
                "attributes": [
                  {
                    "name": "class",
                    "value": "attributes.class",
                    "unescaped": true,
                  },
                  { "name": "href", "value": "href", "unescaped": false },
                ],
                "children": [["Interpolation", "name"]],
                "self_closing": false,
              },
            ],
          ],
        },
      ],
      [
        "MixinCall",
        {
          "name": "link",
          "args": ["/foo", "foo"],
          "block": [],
          "attrs": [["class", "btn"]],
        },
      ],
    ],
  })
}

///|
test "mixin with default argument" {
  let pug =
    #|mixin article(title="Default Title")
    #|  h1= title
    #|+article()
    #|+article("Custom")
  inspect(@pug.render(pug), content="<h1>Default Title</h1><h1>Custom</h1>")
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "MixinDef",
        {
          "name": "article",
          "params": [["title", "Default Title"]],
          "body": [
            [
              "Element",
              {
                "tag": "h1",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Interpolation", "title"]],
                "self_closing": false,
              },
            ],
          ],
        },
      ],
      ["MixinCall", { "name": "article", "args": [], "block": [], "attrs": [] }],
      [
        "MixinCall",
        { "name": "article", "args": ["Custom"], "block": [], "attrs": [] },
      ],
    ],
  })
}

///|
test "mixin with rest arguments" {
  let pug =
    #|mixin list(id, ...items)
    #|  ul(id=id)
    #|    each item in items
    #|      li= item
    #|+list("menu", "Home", "About", "Contact")
  inspect(
    @pug.render(pug),
    content="<ul id=\"menu\"><li>Home</li><li>About</li><li>Contact</li></ul>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "MixinDef",
        {
          "name": "list",
          "params": [["id", ""], ["...items", ""]],
          "body": [
            [
              "Element",
              {
                "tag": "ul",
                "id": "",
                "classes": [],
                "attributes": [
                  { "name": "id", "value": "id", "unescaped": false },
                ],
                "children": [
                  [
                    "Each",
                    {
                      "item_var": "item",
                      "index_var": "",
                      "collection": "items",
                      "body": [
                        [
                          "Element",
                          {
                            "tag": "li",
                            "id": "",
                            "classes": [],
                            "attributes": [],
                            "children": [["Interpolation", "item"]],
                            "self_closing": false,
                          },
                        ],
                      ],
                      "else_body": [],
                    },
                  ],
                ],
                "self_closing": false,
              },
            ],
          ],
        },
      ],
      [
        "MixinCall",
        {
          "name": "list",
          "args": ["menu", "Home", "About", "Contact"],
          "block": [],
          "attrs": [],
        },
      ],
    ],
  })
}

///|
test "multiple mixin calls" {
  let pug =
    #|mixin item(text)
    #|  li= text
    #|ul
    #|  +item("First")
    #|  +item("Second")
    #|  +item("Third")
  inspect(
    @pug.render(pug),
    content="<ul><li>First</li><li>Second</li><li>Third</li></ul>",
  )
  json_inspect(@pug.parse(pug).to_test_json(), content={
    "nodes": [
      [
        "MixinDef",
        {
          "name": "item",
          "params": [["text", ""]],
          "body": [
            [
              "Element",
              {
                "tag": "li",
                "id": "",
                "classes": [],
                "attributes": [],
                "children": [["Interpolation", "text"]],
                "self_closing": false,
              },
            ],
          ],
        },
      ],
      [
        "Element",
        {
          "tag": "ul",
          "id": "",
          "classes": [],
          "attributes": [],
          "children": [
            [
              "MixinCall",
              { "name": "item", "args": ["First"], "block": [], "attrs": [] },
            ],
            [
              "MixinCall",
              { "name": "item", "args": ["Second"], "block": [], "attrs": [] },
            ],
            [
              "MixinCall",
              { "name": "item", "args": ["Third"], "block": [], "attrs": [] },
            ],
          ],
          "self_closing": false,
        },
      ],
    ],
  })
}

///|
test "unless - basic true" {
  let pug =
    #|unless loggedIn
    #|  p Please log in
  let locals = Locals::new()
  locals.set("loggedIn", "true")
  json_inspect(render_with_locals(pug, locals), content="")
}

///|
test "unless - basic false" {
  let pug =
    #|unless loggedIn
    #|  p Please log in
  let locals = Locals::new()
  locals.set("loggedIn", "false")
  json_inspect(render_with_locals(pug, locals), content="<p>Please log in</p>")
}

///|
test "doctype - xml" {
  let pug =
    #|doctype xml
  json_inspect(
    render(pug),
    content="<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
  )
}

///|
test "doctype - strict" {
  let pug =
    #|doctype strict
  json_inspect(
    render(pug),
    content="<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">",
  )
}

///|
test "doctype - 1.1" {
  let pug =
    #|doctype 1.1
  json_inspect(
    render(pug),
    content="<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.1//EN\" \"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd\">",
  )
}

///|
test "tag interpolation - basic" {
  let pug =
    #|p Hello #[strong world]
  json_inspect(render(pug), content="<p>Hello <strong>world</strong></p>")
}

///|
test "tag interpolation - multiple" {
  let pug =
    #|p Click #[a(href="/") here] or #[a(href="/about") there]
  json_inspect(
    render(pug),
    content="<p>Click <a href=\"/\">here</a> or <a href=\"/about\">there</a></p>",
  )
}

///|
test "mixin default values - use default" {
  let pug =
    #|mixin greet(name='World')
    #|  p Hello #{name}
    #|+greet()
  json_inspect(render(pug), content="<p>Hello World</p>")
}

///|
test "mixin default values - override default" {
  let pug =
    #|mixin greet(name='World')
    #|  p Hello #{name}
    #|+greet('MoonBit')
  json_inspect(render(pug), content="<p>Hello MoonBit</p>")
}

///|
test "buffered code - escaped" {
  let pug =
    #|p= title
  let locals = Locals::new()
  locals.set("title", "<script>alert('xss')</script>")
  json_inspect(
    render_with_locals(pug, locals),
    content="<p>&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;</p>",
  )
}

///|
test "buffered code - unescaped" {
  let pug =
    #|p!= content
  let locals = Locals::new()
  locals.set("content", "<strong>Bold</strong>")
  json_inspect(
    render_with_locals(pug, locals),
    content="<p><strong>Bold</strong></p>",
  )
}

///|
test "dynamic expression - variable in attribute" {
  let pug =
    #|a(href=url) Link
  let locals = Locals::new()
  locals.set("url", "/path/to/page")
  json_inspect(
    render_with_locals(pug, locals),
    content="<a href=\"/path/to/page\">Link</a>",
  )
}

///|
test "dynamic expression - string concatenation" {
  let pug =
    #|a(href=baseUrl + '/users') Users
  let locals = Locals::new()
  locals.set("baseUrl", "https://api.example.com")
  json_inspect(
    render_with_locals(pug, locals),
    content="<a href=\"https://api.example.com/users\">Users</a>",
  )
}

///|
test "include with filter - markdown" {
  let registry = TemplateRegistry::new()
  registry.register("article.md", "# Hello\n\nWorld")
  let pug =
    #|div
    #|  include:markdown article.md
  let locals = Locals::new()
  json_inspect(
    render_with_registry(pug, locals, registry),
    content="<div><h1>Hello</h1><p>World</p></div>",
  )
}

///|
test "include with filter - plain" {
  let registry = TemplateRegistry::new()
  registry.register("code.txt", "fn main() { println(\"hi\") }")
  let pug =
    #|pre
    #|  include:plain code.txt
  let locals = Locals::new()
  json_inspect(
    render_with_registry(pug, locals, registry),
    content="<pre>fn main() { println(\"hi\") }</pre>",
  )
}

///|
test "logical operator - and (&&) both true" {
  let pug =
    #|if loggedIn && isAdmin
    #|  p Welcome admin
  let locals = Locals::new()
  locals.set("loggedIn", "true")
  locals.set("isAdmin", "true")
  json_inspect(render_with_locals(pug, locals), content="<p>Welcome admin</p>")
}

///|
test "logical operator - and (&&) one false" {
  let pug =
    #|if loggedIn && isAdmin
    #|  p Welcome admin
  let locals = Locals::new()
  locals.set("loggedIn", "true")
  locals.set("isAdmin", "false")
  json_inspect(render_with_locals(pug, locals), content="")
}

///|
test "logical operator - or (||) both false" {
  let pug =
    #|if isAdmin || isModerator
    #|  p You have privileges
  let locals = Locals::new()
  locals.set("isAdmin", "false")
  locals.set("isModerator", "false")
  json_inspect(render_with_locals(pug, locals), content="")
}

///|
test "logical operator - or (||) one true" {
  let pug =
    #|if isAdmin || isModerator
    #|  p You have privileges
  let locals = Locals::new()
  locals.set("isAdmin", "false")
  locals.set("isModerator", "true")
  json_inspect(
    render_with_locals(pug, locals),
    content="<p>You have privileges</p>",
  )
}

///|
test "ternary expression - true condition" {
  let pug =
    #|div(class=active ? 'on' : 'off')
  let locals = Locals::new()
  locals.set("active", "true")
  json_inspect(
    render_with_locals(pug, locals),
    content="<div class=\"on\"></div>",
  )
}

///|
test "ternary expression - false condition" {
  let pug =
    #|div(class=active ? 'on' : 'off')
  let locals = Locals::new()
  locals.set("active", "false")
  json_inspect(
    render_with_locals(pug, locals),
    content="<div class=\"off\"></div>",
  )
}

///|
test "mixin rest params - basic" {
  let pug =
    #|mixin list(id, ...items)
    #|  ul(id=id)
    #|    each item in items
    #|      li= item
    #|+list('my-list', 'one', 'two', 'three')
  json_inspect(
    render(pug),
    content="<ul id=\"my-list\"><li>one</li><li>two</li><li>three</li></ul>",
  )
}

///|
test "self-closing tag - explicit" {
  let pug =
    #|foo/
  json_inspect(render(pug), content="<foo/>")
}

///|
test "self-closing tag - with attributes" {
  let pug =
    #|xml-node(attr="value")/
  json_inspect(render(pug), content="<xml-node attr=\"value\"/>")
}

///|
test "each with object - key value" {
  let pug =
    #|ul
    #|  each val, key in obj
    #|    li #{key}: #{val}
  let locals = Locals::new()
  locals.set_object("obj", { "name": "John", "age": "30" })
  json_inspect(
    render_with_locals(pug, locals),
    content="<ul><li>name: John</li><li>age: 30</li></ul>",
  )
}

///|
test "pretty print - basic" {
  let pug =
    #|html
    #|  head
    #|    title Hello
    #|  body
    #|    p World
  json_inspect(
    render_pretty(pug),
    content=(
      #|<html>
      #|  <head>
      #|    <title>Hello</title>
      #|  </head>
      #|  <body>
      #|    <p>World</p>
      #|  </body>
      #|</html>
      #|
    ),
  )
}
