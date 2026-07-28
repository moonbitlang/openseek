///|
/// Render token arrays independently of the toolchain's pretty-print width.
/// Each token already has a benchmark-defined compact representation.
priv struct TokenList(Array[@html5.Token])

///|
fn TokenList::to_string(self : TokenList) -> String {
  let out = StringBuilder::new()
  out.write_string("[")
  let mut first = true
  for token in self.0 {
    if first {
      first = false
    } else {
      out.write_string(", ")
    }
    out.write_string(token.to_string())
  }
  out.write_string("]")
  out.to_string()
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00a0_4555" {
  let (tokens, _) = @html5.tokenize("&#x00a0;")
  inspect(TokenList(tokens).to_string(), content="[Character(' '), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00a1_4556" {
  let (tokens, _) = @html5.tokenize("&#x00a1;")
  inspect(TokenList(tokens).to_string(), content="[Character('¡'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00a2_4557" {
  let (tokens, _) = @html5.tokenize("&#x00a2;")
  inspect(TokenList(tokens).to_string(), content="[Character('¢'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00a3_4558" {
  let (tokens, _) = @html5.tokenize("&#x00a3;")
  inspect(TokenList(tokens).to_string(), content="[Character('£'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00a4_4559" {
  let (tokens, _) = @html5.tokenize("&#x00a4;")
  inspect(TokenList(tokens).to_string(), content="[Character('¤'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00a5_4560" {
  let (tokens, _) = @html5.tokenize("&#x00a5;")
  inspect(TokenList(tokens).to_string(), content="[Character('¥'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00a6_4561" {
  let (tokens, _) = @html5.tokenize("&#x00a6;")
  inspect(TokenList(tokens).to_string(), content="[Character('¦'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00a7_4562" {
  let (tokens, _) = @html5.tokenize("&#x00a7;")
  inspect(TokenList(tokens).to_string(), content="[Character('§'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00a8_4563" {
  let (tokens, _) = @html5.tokenize("&#x00a8;")
  inspect(TokenList(tokens).to_string(), content="[Character('¨'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00a9_4564" {
  let (tokens, _) = @html5.tokenize("&#x00a9;")
  inspect(TokenList(tokens).to_string(), content="[Character('©'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00aa_4565" {
  let (tokens, _) = @html5.tokenize("&#x00aa;")
  inspect(TokenList(tokens).to_string(), content="[Character('ª'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ab_4566" {
  let (tokens, _) = @html5.tokenize("&#x00ab;")
  inspect(TokenList(tokens).to_string(), content="[Character('«'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ac_4567" {
  let (tokens, _) = @html5.tokenize("&#x00ac;")
  inspect(TokenList(tokens).to_string(), content="[Character('¬'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ad_4568" {
  let (tokens, _) = @html5.tokenize("&#x00ad;")
  inspect(TokenList(tokens).to_string(), content="[Character('\\u{ad}'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ae_4569" {
  let (tokens, _) = @html5.tokenize("&#x00ae;")
  inspect(TokenList(tokens).to_string(), content="[Character('®'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00af_4570" {
  let (tokens, _) = @html5.tokenize("&#x00af;")
  inspect(TokenList(tokens).to_string(), content="[Character('¯'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00b0_4571" {
  let (tokens, _) = @html5.tokenize("&#x00b0;")
  inspect(TokenList(tokens).to_string(), content="[Character('°'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00b1_4572" {
  let (tokens, _) = @html5.tokenize("&#x00b1;")
  inspect(TokenList(tokens).to_string(), content="[Character('±'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00b2_4573" {
  let (tokens, _) = @html5.tokenize("&#x00b2;")
  inspect(TokenList(tokens).to_string(), content="[Character('²'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00b3_4574" {
  let (tokens, _) = @html5.tokenize("&#x00b3;")
  inspect(TokenList(tokens).to_string(), content="[Character('³'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00b4_4575" {
  let (tokens, _) = @html5.tokenize("&#x00b4;")
  inspect(TokenList(tokens).to_string(), content="[Character('´'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00b5_4576" {
  let (tokens, _) = @html5.tokenize("&#x00b5;")
  inspect(TokenList(tokens).to_string(), content="[Character('µ'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00b6_4577" {
  let (tokens, _) = @html5.tokenize("&#x00b6;")
  inspect(TokenList(tokens).to_string(), content="[Character('¶'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00b7_4578" {
  let (tokens, _) = @html5.tokenize("&#x00b7;")
  inspect(TokenList(tokens).to_string(), content="[Character('·'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00b8_4579" {
  let (tokens, _) = @html5.tokenize("&#x00b8;")
  inspect(TokenList(tokens).to_string(), content="[Character('¸'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00b9_4580" {
  let (tokens, _) = @html5.tokenize("&#x00b9;")
  inspect(TokenList(tokens).to_string(), content="[Character('¹'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ba_4581" {
  let (tokens, _) = @html5.tokenize("&#x00ba;")
  inspect(TokenList(tokens).to_string(), content="[Character('º'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00bb_4582" {
  let (tokens, _) = @html5.tokenize("&#x00bb;")
  inspect(TokenList(tokens).to_string(), content="[Character('»'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00bc_4583" {
  let (tokens, _) = @html5.tokenize("&#x00bc;")
  inspect(TokenList(tokens).to_string(), content="[Character('¼'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00bd_4584" {
  let (tokens, _) = @html5.tokenize("&#x00bd;")
  inspect(TokenList(tokens).to_string(), content="[Character('½'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00be_4585" {
  let (tokens, _) = @html5.tokenize("&#x00be;")
  inspect(TokenList(tokens).to_string(), content="[Character('¾'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00bf_4586" {
  let (tokens, _) = @html5.tokenize("&#x00bf;")
  inspect(TokenList(tokens).to_string(), content="[Character('¿'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00c0_4587" {
  let (tokens, _) = @html5.tokenize("&#x00c0;")
  inspect(TokenList(tokens).to_string(), content="[Character('À'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00c1_4588" {
  let (tokens, _) = @html5.tokenize("&#x00c1;")
  inspect(TokenList(tokens).to_string(), content="[Character('Á'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00c2_4589" {
  let (tokens, _) = @html5.tokenize("&#x00c2;")
  inspect(TokenList(tokens).to_string(), content="[Character('Â'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00c3_4590" {
  let (tokens, _) = @html5.tokenize("&#x00c3;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ã'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00c4_4591" {
  let (tokens, _) = @html5.tokenize("&#x00c4;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ä'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00c5_4592" {
  let (tokens, _) = @html5.tokenize("&#x00c5;")
  inspect(TokenList(tokens).to_string(), content="[Character('Å'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00c6_4593" {
  let (tokens, _) = @html5.tokenize("&#x00c6;")
  inspect(TokenList(tokens).to_string(), content="[Character('Æ'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00c7_4594" {
  let (tokens, _) = @html5.tokenize("&#x00c7;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ç'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00c8_4595" {
  let (tokens, _) = @html5.tokenize("&#x00c8;")
  inspect(TokenList(tokens).to_string(), content="[Character('È'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00c9_4596" {
  let (tokens, _) = @html5.tokenize("&#x00c9;")
  inspect(TokenList(tokens).to_string(), content="[Character('É'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ca_4597" {
  let (tokens, _) = @html5.tokenize("&#x00ca;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ê'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00cb_4598" {
  let (tokens, _) = @html5.tokenize("&#x00cb;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ë'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00cc_4599" {
  let (tokens, _) = @html5.tokenize("&#x00cc;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ì'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00cd_4600" {
  let (tokens, _) = @html5.tokenize("&#x00cd;")
  inspect(TokenList(tokens).to_string(), content="[Character('Í'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ce_4601" {
  let (tokens, _) = @html5.tokenize("&#x00ce;")
  inspect(TokenList(tokens).to_string(), content="[Character('Î'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00cf_4602" {
  let (tokens, _) = @html5.tokenize("&#x00cf;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ï'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00d0_4603" {
  let (tokens, _) = @html5.tokenize("&#x00d0;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ð'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00d1_4604" {
  let (tokens, _) = @html5.tokenize("&#x00d1;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ñ'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00d2_4605" {
  let (tokens, _) = @html5.tokenize("&#x00d2;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ò'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00d3_4606" {
  let (tokens, _) = @html5.tokenize("&#x00d3;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ó'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00d4_4607" {
  let (tokens, _) = @html5.tokenize("&#x00d4;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ô'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00d5_4608" {
  let (tokens, _) = @html5.tokenize("&#x00d5;")
  inspect(TokenList(tokens).to_string(), content="[Character('Õ'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00d6_4609" {
  let (tokens, _) = @html5.tokenize("&#x00d6;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ö'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00d7_4610" {
  let (tokens, _) = @html5.tokenize("&#x00d7;")
  inspect(TokenList(tokens).to_string(), content="[Character('×'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00d8_4611" {
  let (tokens, _) = @html5.tokenize("&#x00d8;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ø'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00d9_4612" {
  let (tokens, _) = @html5.tokenize("&#x00d9;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ù'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00da_4613" {
  let (tokens, _) = @html5.tokenize("&#x00da;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ú'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00db_4614" {
  let (tokens, _) = @html5.tokenize("&#x00db;")
  inspect(TokenList(tokens).to_string(), content="[Character('Û'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00dc_4615" {
  let (tokens, _) = @html5.tokenize("&#x00dc;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ü'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00dd_4616" {
  let (tokens, _) = @html5.tokenize("&#x00dd;")
  inspect(TokenList(tokens).to_string(), content="[Character('Ý'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00de_4617" {
  let (tokens, _) = @html5.tokenize("&#x00de;")
  inspect(TokenList(tokens).to_string(), content="[Character('Þ'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00df_4618" {
  let (tokens, _) = @html5.tokenize("&#x00df;")
  inspect(TokenList(tokens).to_string(), content="[Character('ß'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00e0_4619" {
  let (tokens, _) = @html5.tokenize("&#x00e0;")
  inspect(TokenList(tokens).to_string(), content="[Character('à'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00e1_4620" {
  let (tokens, _) = @html5.tokenize("&#x00e1;")
  inspect(TokenList(tokens).to_string(), content="[Character('á'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00e2_4621" {
  let (tokens, _) = @html5.tokenize("&#x00e2;")
  inspect(TokenList(tokens).to_string(), content="[Character('â'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00e3_4622" {
  let (tokens, _) = @html5.tokenize("&#x00e3;")
  inspect(TokenList(tokens).to_string(), content="[Character('ã'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00e4_4623" {
  let (tokens, _) = @html5.tokenize("&#x00e4;")
  inspect(TokenList(tokens).to_string(), content="[Character('ä'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00e5_4624" {
  let (tokens, _) = @html5.tokenize("&#x00e5;")
  inspect(TokenList(tokens).to_string(), content="[Character('å'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00e6_4625" {
  let (tokens, _) = @html5.tokenize("&#x00e6;")
  inspect(TokenList(tokens).to_string(), content="[Character('æ'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00e7_4626" {
  let (tokens, _) = @html5.tokenize("&#x00e7;")
  inspect(TokenList(tokens).to_string(), content="[Character('ç'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00e8_4627" {
  let (tokens, _) = @html5.tokenize("&#x00e8;")
  inspect(TokenList(tokens).to_string(), content="[Character('è'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00e9_4628" {
  let (tokens, _) = @html5.tokenize("&#x00e9;")
  inspect(TokenList(tokens).to_string(), content="[Character('é'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ea_4629" {
  let (tokens, _) = @html5.tokenize("&#x00ea;")
  inspect(TokenList(tokens).to_string(), content="[Character('ê'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00eb_4630" {
  let (tokens, _) = @html5.tokenize("&#x00eb;")
  inspect(TokenList(tokens).to_string(), content="[Character('ë'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ec_4631" {
  let (tokens, _) = @html5.tokenize("&#x00ec;")
  inspect(TokenList(tokens).to_string(), content="[Character('ì'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ed_4632" {
  let (tokens, _) = @html5.tokenize("&#x00ed;")
  inspect(TokenList(tokens).to_string(), content="[Character('í'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ee_4633" {
  let (tokens, _) = @html5.tokenize("&#x00ee;")
  inspect(TokenList(tokens).to_string(), content="[Character('î'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ef_4634" {
  let (tokens, _) = @html5.tokenize("&#x00ef;")
  inspect(TokenList(tokens).to_string(), content="[Character('ï'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00f0_4635" {
  let (tokens, _) = @html5.tokenize("&#x00f0;")
  inspect(TokenList(tokens).to_string(), content="[Character('ð'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00f1_4636" {
  let (tokens, _) = @html5.tokenize("&#x00f1;")
  inspect(TokenList(tokens).to_string(), content="[Character('ñ'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00f2_4637" {
  let (tokens, _) = @html5.tokenize("&#x00f2;")
  inspect(TokenList(tokens).to_string(), content="[Character('ò'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00f3_4638" {
  let (tokens, _) = @html5.tokenize("&#x00f3;")
  inspect(TokenList(tokens).to_string(), content="[Character('ó'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00f4_4639" {
  let (tokens, _) = @html5.tokenize("&#x00f4;")
  inspect(TokenList(tokens).to_string(), content="[Character('ô'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00f5_4640" {
  let (tokens, _) = @html5.tokenize("&#x00f5;")
  inspect(TokenList(tokens).to_string(), content="[Character('õ'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00f6_4641" {
  let (tokens, _) = @html5.tokenize("&#x00f6;")
  inspect(TokenList(tokens).to_string(), content="[Character('ö'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00f7_4642" {
  let (tokens, _) = @html5.tokenize("&#x00f7;")
  inspect(TokenList(tokens).to_string(), content="[Character('÷'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00f8_4643" {
  let (tokens, _) = @html5.tokenize("&#x00f8;")
  inspect(TokenList(tokens).to_string(), content="[Character('ø'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00f9_4644" {
  let (tokens, _) = @html5.tokenize("&#x00f9;")
  inspect(TokenList(tokens).to_string(), content="[Character('ù'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00fa_4645" {
  let (tokens, _) = @html5.tokenize("&#x00fa;")
  inspect(TokenList(tokens).to_string(), content="[Character('ú'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00fb_4646" {
  let (tokens, _) = @html5.tokenize("&#x00fb;")
  inspect(TokenList(tokens).to_string(), content="[Character('û'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00fc_4647" {
  let (tokens, _) = @html5.tokenize("&#x00fc;")
  inspect(TokenList(tokens).to_string(), content="[Character('ü'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00fd_4648" {
  let (tokens, _) = @html5.tokenize("&#x00fd;")
  inspect(TokenList(tokens).to_string(), content="[Character('ý'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00fe_4649" {
  let (tokens, _) = @html5.tokenize("&#x00fe;")
  inspect(TokenList(tokens).to_string(), content="[Character('þ'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u00ff_4650" {
  let (tokens, _) = @html5.tokenize("&#x00ff;")
  inspect(TokenList(tokens).to_string(), content="[Character('ÿ'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_ud7ff_4651" {
  let (tokens, _) = @html5.tokenize("&#xd7ff;")
  inspect(TokenList(tokens).to_string(), content="[Character('퟿'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_ue000_4652" {
  let (tokens, _) = @html5.tokenize("&#xe000;")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('\\u{e000}'), EOF]",
  )
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_ufdcf_4653" {
  let (tokens, _) = @html5.tokenize("&#xfdcf;")
  inspect(TokenList(tokens).to_string(), content="[Character('﷏'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_ufdf0_4654" {
  let (tokens, _) = @html5.tokenize("&#xfdf0;")
  inspect(TokenList(tokens).to_string(), content="[Character('ﷰ'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_ufffd_4655" {
  let (tokens, _) = @html5.tokenize("&#xfffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('�'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u10000_4656" {
  let (tokens, _) = @html5.tokenize("&#x10000;")
  inspect(TokenList(tokens).to_string(), content="[Character('𐀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u1fffd_4657" {
  let (tokens, _) = @html5.tokenize("&#x1fffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('🿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u20000_4658" {
  let (tokens, _) = @html5.tokenize("&#x20000;")
  inspect(TokenList(tokens).to_string(), content="[Character('𠀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u2fffd_4659" {
  let (tokens, _) = @html5.tokenize("&#x2fffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('𯿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u30000_4660" {
  let (tokens, _) = @html5.tokenize("&#x30000;")
  inspect(TokenList(tokens).to_string(), content="[Character('𰀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u3fffd_4661" {
  let (tokens, _) = @html5.tokenize("&#x3fffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('𿿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u40000_4662" {
  let (tokens, _) = @html5.tokenize("&#x40000;")
  inspect(TokenList(tokens).to_string(), content="[Character('񀀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u4fffd_4663" {
  let (tokens, _) = @html5.tokenize("&#x4fffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('񏿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u50000_4664" {
  let (tokens, _) = @html5.tokenize("&#x50000;")
  inspect(TokenList(tokens).to_string(), content="[Character('񐀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u5fffd_4665" {
  let (tokens, _) = @html5.tokenize("&#x5fffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('񟿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u60000_4666" {
  let (tokens, _) = @html5.tokenize("&#x60000;")
  inspect(TokenList(tokens).to_string(), content="[Character('񠀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u6fffd_4667" {
  let (tokens, _) = @html5.tokenize("&#x6fffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('񯿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u70000_4668" {
  let (tokens, _) = @html5.tokenize("&#x70000;")
  inspect(TokenList(tokens).to_string(), content="[Character('񰀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u7fffd_4669" {
  let (tokens, _) = @html5.tokenize("&#x7fffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('񿿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u80000_4670" {
  let (tokens, _) = @html5.tokenize("&#x80000;")
  inspect(TokenList(tokens).to_string(), content="[Character('򀀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u8fffd_4671" {
  let (tokens, _) = @html5.tokenize("&#x8fffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('򏿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u90000_4672" {
  let (tokens, _) = @html5.tokenize("&#x90000;")
  inspect(TokenList(tokens).to_string(), content="[Character('򐀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u9fffd_4673" {
  let (tokens, _) = @html5.tokenize("&#x9fffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('򟿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_ua0000_4674" {
  let (tokens, _) = @html5.tokenize("&#xa0000;")
  inspect(TokenList(tokens).to_string(), content="[Character('򠀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_uafffd_4675" {
  let (tokens, _) = @html5.tokenize("&#xafffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('򯿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_ub0000_4676" {
  let (tokens, _) = @html5.tokenize("&#xb0000;")
  inspect(TokenList(tokens).to_string(), content="[Character('򰀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_ubfffd_4677" {
  let (tokens, _) = @html5.tokenize("&#xbfffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('򿿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_uc0000_4678" {
  let (tokens, _) = @html5.tokenize("&#xc0000;")
  inspect(TokenList(tokens).to_string(), content="[Character('󀀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_ucfffd_4679" {
  let (tokens, _) = @html5.tokenize("&#xcfffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('󏿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_ud0000_4680" {
  let (tokens, _) = @html5.tokenize("&#xd0000;")
  inspect(TokenList(tokens).to_string(), content="[Character('󐀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_udfffd_4681" {
  let (tokens, _) = @html5.tokenize("&#xdfffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('󟿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_ue0000_4682" {
  let (tokens, _) = @html5.tokenize("&#xe0000;")
  inspect(TokenList(tokens).to_string(), content="[Character('󠀀'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_uefffd_4683" {
  let (tokens, _) = @html5.tokenize("&#xefffd;")
  inspect(TokenList(tokens).to_string(), content="[Character('󯿽'), EOF]")
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_uf0000_4684" {
  let (tokens, _) = @html5.tokenize("&#xf0000;")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('\\u{0f0000}'), EOF]",
  )
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_uffffd_4685" {
  let (tokens, _) = @html5.tokenize("&#xffffd;")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('\\u{0ffffd}'), EOF]",
  )
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u100000_4686" {
  let (tokens, _) = @html5.tokenize("&#x100000;")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('\\u{100000}'), EOF]",
  )
}

///|
test "html5lib/tokenizer/numericEntities_valid_numeric_entity_character_u10fffd_4687" {
  let (tokens, _) = @html5.tokenize("&#x10fffd;")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('\\u{10fffd}'), EOF]",
  )
}

///|
test "html5lib/tokenizer/pendingSpecChanges___4688" {
  let (tokens, _) = @html5.tokenize("<!---- >")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-- >\"), EOF]")
}

///|
test "html5lib/tokenizer/test1_correct_doctype_lowercase_4689" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE html>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=None, system_id=None, force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_correct_doctype_uppercase_4690" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE HTML>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=None, system_id=None, force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_correct_doctype_mixed_case_4691" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE HtMl>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=None, system_id=None, force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_correct_doctype_case_with_eof_4692" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE HtMl")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_truncated_doctype_start_4693" {
  let (tokens, _) = @html5.tokenize("<!DOC>")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"DOC\"), EOF]")
}

///|
test "html5lib/tokenizer/test1_doctype_in_error_4694" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE foo>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"foo\"), public_id=None, system_id=None, force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_single_start_tag_4695" {
  let (tokens, _) = @html5.tokenize("<h>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_empty_end_tag_4696" {
  let (tokens, _) = @html5.tokenize("</>")
  inspect(TokenList(tokens).to_string(), content="[EOF]")
}

///|
test "html5lib/tokenizer/test1_empty_start_tag_4697" {
  let (tokens, _) = @html5.tokenize("<>")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('<'), Character('>'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_start_tag_wattribute_4698" {
  let (tokens, _) = @html5.tokenize("<h a='b'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"b\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_start_tag_wattribute_no_quotes_4699" {
  let (tokens, _) = @html5.tokenize("<h a=b>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"b\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_startend_tag_4700" {
  let (tokens, _) = @html5.tokenize("<h></h>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[], self_closing=false), EndTag(name=\"h\"), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_two_unclosed_start_tags_4701" {
  let (tokens, _) = @html5.tokenize("<p>One<p>Two")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"p\", attrs=[], self_closing=false), Character('O'), Character('n'), Character('e'), StartTag(name=\"p\", attrs=[], self_closing=false), Character('T'), Character('w'), Character('o'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_end_tag_wattribute_4702" {
  let (tokens, _) = @html5.tokenize("<h></h a='b'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[], self_closing=false), EndTag(name=\"h\"), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_multiple_atts_4703" {
  let (tokens, _) = @html5.tokenize("<h a='b' c='d'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"b\"}, {name: \"c\", value: \"d\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_multiple_atts_no_space_4704" {
  let (tokens, _) = @html5.tokenize("<h a='b'c='d'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"b\"}, {name: \"c\", value: \"d\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_repeated_attr_4705" {
  let (tokens, _) = @html5.tokenize("<h a='b' a='d'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"b\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_simple_comment_4706" {
  let (tokens, _) = @html5.tokenize("<!--comment-->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"comment\"), EOF]")
}

///|
test "html5lib/tokenizer/test1_comment_central_dash_no_space_4707" {
  let (tokens, _) = @html5.tokenize("<!----->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-\"), EOF]")
}

///|
test "html5lib/tokenizer/test1_comment_two_central_dashes_4708" {
  let (tokens, _) = @html5.tokenize("<!-- --comment -->")
  inspect(
    TokenList(tokens).to_string(),
    content="[Comment(\" --comment \"), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_comment_central_lessthan_bang_4709" {
  let (tokens, _) = @html5.tokenize("<!--<!-->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"<!\"), EOF]")
}

///|
test "html5lib/tokenizer/test1_unfinished_comment_4710" {
  let (tokens, _) = @html5.tokenize("<!--comment")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"comment\"), EOF]")
}

///|
test "html5lib/tokenizer/test1_unfinished_comment_after_start_of_nested_comment_4711" {
  let (tokens, _) = @html5.tokenize("<!-- <!--")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" <!\"), EOF]")
}

///|
test "html5lib/tokenizer/test1_start_of_a_comment_4712" {
  let (tokens, _) = @html5.tokenize("<!-")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-\"), EOF]")
}

///|
test "html5lib/tokenizer/test1_short_comment_4713" {
  let (tokens, _) = @html5.tokenize("<!-->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test1_short_comment_two_4714" {
  let (tokens, _) = @html5.tokenize("<!--->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test1_short_comment_three_4715" {
  let (tokens, _) = @html5.tokenize("<!---->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test1__in_comment_4716" {
  let (tokens, _) = @html5.tokenize("<!-- <test-->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" <test\"), EOF]")
}

///|
test "html5lib/tokenizer/test1__in_comment_4717" {
  let (tokens, _) = @html5.tokenize("<!--<<-->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"<<\"), EOF]")
}

///|
test "html5lib/tokenizer/test1__in_comment_4718" {
  let (tokens, _) = @html5.tokenize("<!-- <!test-->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" <!test\"), EOF]")
}

///|
test "html5lib/tokenizer/test1__in_comment_4719" {
  let (tokens, _) = @html5.tokenize("<!-- <!-test-->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" <!-test\"), EOF]")
}

///|
test "html5lib/tokenizer/test1_nested_comment_4720" {
  let (tokens, _) = @html5.tokenize("<!-- <!--test-->")
  inspect(
    TokenList(tokens).to_string(),
    content="[Comment(\" <!--test\"), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_nested_comment_with_extra__4721" {
  let (tokens, _) = @html5.tokenize("<!-- <<!--test-->")
  inspect(
    TokenList(tokens).to_string(),
    content="[Comment(\" <<!--test\"), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_ampersand_eof_4735" {
  let (tokens, _) = @html5.tokenize("&")
  inspect(TokenList(tokens).to_string(), content="[Character('&'), EOF]")
}

///|
test "html5lib/tokenizer/test1_ampersand_ampersand_eof_4736" {
  let (tokens, _) = @html5.tokenize("&&")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('&'), Character('&'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_ampersand_space_eof_4737" {
  let (tokens, _) = @html5.tokenize("& ")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('&'), Character(' '), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_unfinished_entity_4738" {
  let (tokens, _) = @html5.tokenize("&f")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('&'), Character('f'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_ampersand_number_sign_4739" {
  let (tokens, _) = @html5.tokenize("&#")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('&'), Character('#'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_unfinished_numeric_entity_4740" {
  let (tokens, _) = @html5.tokenize("&#x")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('&'), Character('#'), Character('x'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_entity_with_trailing_semicolon_1_4741" {
  let (tokens, _) = @html5.tokenize("I'm &not;it")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('I'), Character('\\''), Character('m'), Character(' '), Character('¬'), Character('i'), Character('t'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_entity_with_trailing_semicolon_2_4742" {
  let (tokens, _) = @html5.tokenize("I'm &notin;")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('I'), Character('\\''), Character('m'), Character(' '), Character('∉'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_entity_without_trailing_semicolon_1_4743" {
  let (tokens, _) = @html5.tokenize("I'm &notit")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('I'), Character('\\''), Character('m'), Character(' '), Character('¬'), Character('i'), Character('t'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_entity_without_trailing_semicolon_2_4744" {
  let (tokens, _) = @html5.tokenize("I'm &notin")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('I'), Character('\\''), Character('m'), Character(' '), Character('¬'), Character('i'), Character('n'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_partial_entity_match_at_end_of_file_4745" {
  let (tokens, _) = @html5.tokenize("I'm &no")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('I'), Character('\\''), Character('m'), Character(' '), Character('&'), Character('n'), Character('o'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_nonascii_character_reference_name_4746" {
  let (tokens, _) = @html5.tokenize("&¬;")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('&'), Character('¬'), Character(';'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_ascii_decimal_entity_4747" {
  let (tokens, _) = @html5.tokenize("&#0036;")
  inspect(TokenList(tokens).to_string(), content="[Character('$'), EOF]")
}

///|
test "html5lib/tokenizer/test1_ascii_hexadecimal_entity_4748" {
  let (tokens, _) = @html5.tokenize("&#x3f;")
  inspect(TokenList(tokens).to_string(), content="[Character('?'), EOF]")
}

///|
test "html5lib/tokenizer/test1_hexadecimal_entity_in_attribute_4749" {
  let (tokens, _) = @html5.tokenize("<h a='&#x3f;'></h>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"?\"}], self_closing=false), EndTag(name=\"h\"), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_entity_in_attribute_without_semicolon_ending_in_x_4750" {
  let (tokens, _) = @html5.tokenize("<h a='&notx'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"&notx\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_entity_in_attribute_without_semicolon_ending_in_1_4751" {
  let (tokens, _) = @html5.tokenize("<h a='&not1'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"&not1\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_entity_in_attribute_without_semicolon_ending_in_i_4752" {
  let (tokens, _) = @html5.tokenize("<h a='&noti'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"&noti\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_entity_in_attribute_without_semicolon_4753" {
  let (tokens, _) = @html5.tokenize("<h a='&COPY'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"©\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_unquoted_attribute_ending_in_ampersand_4754" {
  let (tokens, _) = @html5.tokenize("<s o=& t>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"s\", attrs=[{name: \"o\", value: \"&\"}, {name: \"t\", value: \"\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_unquoted_attribute_at_end_of_tag_with_final_charac_4755" {
  let (tokens, _) = @html5.tokenize("<a a=a&>foo")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"a\", attrs=[{name: \"a\", value: \"a&\"}], self_closing=false), Character('f'), Character('o'), Character('o'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_plaintext_element_4756" {
  let (tokens, _) = @html5.tokenize("<plaintext>foobar")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"plaintext\", attrs=[], self_closing=false), Character('f'), Character('o'), Character('o'), Character('b'), Character('a'), Character('r'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test1_open_angled_bracket_in_unquoted_attribute_value_st_4757" {
  let (tokens, _) = @html5.tokenize("<a a=f<>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"a\", attrs=[{name: \"a\", value: \"f<\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_without_name_4758" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_without_space_before_name_4759" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPEhtml>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=None, system_id=None, force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_incorrect_doctype_without_a_space_before_name_4760" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPEfoo>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"foo\"), public_id=None, system_id=None, force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_with_publicid_4761" {
  let (tokens, _) = @html5.tokenize(
    "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML Transitional 4.01//EN\">",
  )
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=Some(\"-//W3C//DTD HTML Transitional 4.01//EN\"), system_id=None, force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_with_eof_after_public_4762" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE html PUBLIC")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_with_eof_after_public__4763" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE html PUBLIC '")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_with_eof_after_public_x_4764" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE html PUBLIC 'x")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=Some(\"x\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_with_systemid_4765" {
  let (tokens, _) = @html5.tokenize(
    "<!DOCTYPE html SYSTEM \"-//W3C//DTD HTML Transitional 4.01//EN\">",
  )
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=None, system_id=Some(\"-//W3C//DTD HTML Transitional 4.01//EN\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_with_singlequoted_systemid_4766" {
  let (tokens, _) = @html5.tokenize(
    "<!DOCTYPE html SYSTEM '-//W3C//DTD HTML Transitional 4.01//EN'>",
  )
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=None, system_id=Some(\"-//W3C//DTD HTML Transitional 4.01//EN\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_with_publicid_and_systemid_4767" {
  let (tokens, _) = @html5.tokenize(
    "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML Transitional 4.01//EN\" \"-//W3C//DTD HTML Transitional 4.01//EN\">",
  )
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=Some(\"-//W3C//DTD HTML Transitional 4.01//EN\"), system_id=Some(\"-//W3C//DTD HTML Transitional 4.01//EN\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_with_in_doublequoted_publicid_4768" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE html PUBLIC \">x")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=Some(\"\"), system_id=None, force_quirks=true), Character('x'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_with_in_singlequoted_publicid_4769" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE html PUBLIC '>x")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=Some(\"\"), system_id=None, force_quirks=true), Character('x'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_with_in_doublequoted_systemid_4770" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE html PUBLIC \"foo\" \">x")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=Some(\"foo\"), system_id=Some(\"\"), force_quirks=true), Character('x'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doctype_with_in_singlequoted_systemid_4771" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE html PUBLIC 'foo' '>x")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=Some(\"foo\"), system_id=Some(\"\"), force_quirks=true), Character('x'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_incomplete_doctype_4772" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE html ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"html\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_numeric_entity_representing_the_nul_character_4773" {
  let (tokens, _) = @html5.tokenize("&#0000;")
  inspect(TokenList(tokens).to_string(), content="[Character('�'), EOF]")
}

///|
test "html5lib/tokenizer/test2_hexadecimal_entity_representing_the_nul_character_4774" {
  let (tokens, _) = @html5.tokenize("&#x0000;")
  inspect(TokenList(tokens).to_string(), content="[Character('�'), EOF]")
}

///|
test "html5lib/tokenizer/test2_numeric_entity_representing_a_codepoint_after_1114_4775" {
  let (tokens, _) = @html5.tokenize("&#2225222;")
  inspect(TokenList(tokens).to_string(), content="[Character('�'), EOF]")
}

///|
test "html5lib/tokenizer/test2_hexadecimal_entity_representing_a_codepoint_after__4776" {
  let (tokens, _) = @html5.tokenize("&#x1010FFFF;")
  inspect(TokenList(tokens).to_string(), content="[Character('�'), EOF]")
}

///|
test "html5lib/tokenizer/test2_hexadecimal_entity_pair_representing_a_surrogate_p_4777" {
  let (tokens, _) = @html5.tokenize("&#xD869;&#xDED6;")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('�'), Character('�'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_hexadecimal_entity_with_mixed_uppercase_and_lowerc_4778" {
  let (tokens, _) = @html5.tokenize("&#xaBcD;")
  inspect(TokenList(tokens).to_string(), content="[Character('ꯍ'), EOF]")
}

///|
test "html5lib/tokenizer/test2_entity_without_a_name_4779" {
  let (tokens, _) = @html5.tokenize("&;")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('&'), Character(';'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_unescaped_ampersand_in_attribute_value_4780" {
  let (tokens, _) = @html5.tokenize("<h a='&'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"&\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_starttag_containing__4781" {
  let (tokens, _) = @html5.tokenize("<a<b>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"a<b\", attrs=[], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_nonvoid_element_containing_trailing__4782" {
  let (tokens, _) = @html5.tokenize("<h/>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[], self_closing=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_void_element_with_permitted_slash_4783" {
  let (tokens, _) = @html5.tokenize("<br/>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"br\", attrs=[], self_closing=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_void_element_with_permitted_slash_with_attribute_4784" {
  let (tokens, _) = @html5.tokenize("<br foo='bar'/>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"br\", attrs=[{name: \"foo\", value: \"bar\"}], self_closing=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_starttag_containing__4785" {
  let (tokens, _) = @html5.tokenize("<h/a='b'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"b\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doublequoted_attribute_value_4786" {
  let (tokens, _) = @html5.tokenize("<h a=\"b\">")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"b\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_unescaped__4787" {
  let (tokens, _) = @html5.tokenize("</")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('<'), Character('/'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_illegal_end_tag_name_4788" {
  let (tokens, _) = @html5.tokenize("</1>")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"1\"), EOF]")
}

///|
test "html5lib/tokenizer/test2_simili_processing_instruction_4789" {
  let (tokens, _) = @html5.tokenize("<?namespace>")
  inspect(
    TokenList(tokens).to_string(),
    content="[Comment(\"?namespace\"), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_a_bogus_comment_stops_at_even_if_preceded_by_two_d_4790" {
  let (tokens, _) = @html5.tokenize("<?foo-->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"?foo--\"), EOF]")
}

///|
test "html5lib/tokenizer/test2_unescaped__4791" {
  let (tokens, _) = @html5.tokenize("foo < bar")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('f'), Character('o'), Character('o'), Character(' '), Character('<'), Character(' '), Character('b'), Character('a'), Character('r'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_null_byte_replacement_4792" {
  let (tokens, _) = @html5.tokenize("\u{00}")
  inspect(TokenList(tokens).to_string(), content="[Character('\\u{00}'), EOF]")
}

///|
test "html5lib/tokenizer/test2_comment_with_dash_4793" {
  let (tokens, _) = @html5.tokenize("<!---x")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-x\"), EOF]")
}

///|
test "html5lib/tokenizer/test2_entity_newline_4794" {
  let (tokens, _) = @html5.tokenize("\nx\n&gt;\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('\\n'), Character('x'), Character('\\n'), Character('>'), Character('\\n'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_start_tag_with_no_attributes_but_space_before_the__4795" {
  let (tokens, _) = @html5.tokenize("<h >")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_empty_attribute_followed_by_uppercase_attribute_4796" {
  let (tokens, _) = @html5.tokenize("<h a B=''>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"\"}, {name: \"b\", value: \"\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_doublequote_after_attribute_name_4797" {
  let (tokens, _) = @html5.tokenize("<h a \">")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"\"}, {name: \"\\\"\", value: \"\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_singlequote_after_attribute_name_4798" {
  let (tokens, _) = @html5.tokenize("<h a '>")
  inspect(
    TokenList(tokens).to_string(),
    content="[StartTag(name=\"h\", attrs=[{name: \"a\", value: \"\"}, {name: \"'\", value: \"\"}], self_closing=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_empty_end_tag_with_following_characters_4799" {
  let (tokens, _) = @html5.tokenize("a</>bc")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('a'), Character('b'), Character('c'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_empty_end_tag_with_following_tag_4800" {
  let (tokens, _) = @html5.tokenize("a</><b>c")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('a'), StartTag(name=\"b\", attrs=[], self_closing=false), Character('c'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_empty_end_tag_with_following_comment_4801" {
  let (tokens, _) = @html5.tokenize("a</><!--b-->c")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('a'), Comment(\"b\"), Character('c'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test2_empty_end_tag_with_following_end_tag_4802" {
  let (tokens, _) = @html5.tokenize("a</></b>c")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('a'), EndTag(name=\"b\"), Character('c'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3__4871" {
  let (tokens, _) = @html5.tokenize("<")
  inspect(TokenList(tokens).to_string(), content="[Character('<'), EOF]")
}

///|
test "html5lib/tokenizer/test3_u0000_4872" {
  let (tokens, _) = @html5.tokenize("<\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('<'), Character('\\u{00}'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_u0009_4873" {
  let (tokens, _) = @html5.tokenize("<\t")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('<'), Character('\\t'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_u000a_4874" {
  let (tokens, _) = @html5.tokenize("<\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('<'), Character('\\n'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_u000b_4875" {
  let (tokens, _) = @html5.tokenize("<\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('<'), Character('\\u{0b}'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_u000c_4876" {
  let (tokens, _) = @html5.tokenize("<\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('<'), Character('\\u{0c}'), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3___4877" {
  let (tokens, _) = @html5.tokenize("< ")
  inspect(
    TokenList(tokens).to_string(),
    content="[Character('<'), Character(' '), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3__4878" {
  let (tokens, _) = @html5.tokenize("<!")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u0000_4879" {
  let (tokens, _) = @html5.tokenize("<!\u{00}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"�\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u0009_4880" {
  let (tokens, _) = @html5.tokenize("<!\t")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\\t\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u000a_4881" {
  let (tokens, _) = @html5.tokenize("<!\n")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\\n\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u000b_4882" {
  let (tokens, _) = @html5.tokenize("<!\u{0b}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\\u{0b}\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u000c_4883" {
  let (tokens, _) = @html5.tokenize("<!\u{0c}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\\u{0c}\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4884" {
  let (tokens, _) = @html5.tokenize("<! ")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" \"), EOF]")
}

///|
test "html5lib/tokenizer/test3__u0000_4885" {
  let (tokens, _) = @html5.tokenize("<! \u{00}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" �\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4886" {
  let (tokens, _) = @html5.tokenize("<!!")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"!\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4887" {
  let (tokens, _) = @html5.tokenize("<!\"")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\\\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4888" {
  let (tokens, _) = @html5.tokenize("<!&")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"&\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4889" {
  let (tokens, _) = @html5.tokenize("<!'")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"'\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4890" {
  let (tokens, _) = @html5.tokenize("<!-")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4891" {
  let (tokens, _) = @html5.tokenize("<!--")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u0000_4892" {
  let (tokens, _) = @html5.tokenize("<!--\u{00}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"�\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u0009_4893" {
  let (tokens, _) = @html5.tokenize("<!--\t")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\\t\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u000a_4894" {
  let (tokens, _) = @html5.tokenize("<!--\n")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\\n\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u000b_4895" {
  let (tokens, _) = @html5.tokenize("<!--\u{0b}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\\u{0b}\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u000c_4896" {
  let (tokens, _) = @html5.tokenize("<!--\u{0c}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\\u{0c}\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4897" {
  let (tokens, _) = @html5.tokenize("<!-- ")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" \"), EOF]")
}

///|
test "html5lib/tokenizer/test3__u0000_4898" {
  let (tokens, _) = @html5.tokenize("<!-- \u{00}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" �\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__u0009_4899" {
  let (tokens, _) = @html5.tokenize("<!-- \t")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" \\t\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__u000a_4900" {
  let (tokens, _) = @html5.tokenize("<!-- \n")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" \\n\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__u000b_4901" {
  let (tokens, _) = @html5.tokenize("<!-- \u{0b}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" \\u{0b}\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__u000c_4902" {
  let (tokens, _) = @html5.tokenize("<!-- \u{0c}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" \\u{0c}\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4903" {
  let (tokens, _) = @html5.tokenize("<!--  ")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"  \"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4904" {
  let (tokens, _) = @html5.tokenize("<!-- !")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" !\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4905" {
  let (tokens, _) = @html5.tokenize("<!-- \"")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" \\\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4906" {
  let (tokens, _) = @html5.tokenize("<!-- &")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" &\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4907" {
  let (tokens, _) = @html5.tokenize("<!-- '")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" '\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4908" {
  let (tokens, _) = @html5.tokenize("<!-- ,")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" ,\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4909" {
  let (tokens, _) = @html5.tokenize("<!-- -")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" \"), EOF]")
}

///|
test "html5lib/tokenizer/test3__u0000_4910" {
  let (tokens, _) = @html5.tokenize("<!-- -\u{00}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -�\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__u0009_4911" {
  let (tokens, _) = @html5.tokenize("<!-- -\t")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -\\t\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__u000a_4912" {
  let (tokens, _) = @html5.tokenize("<!-- -\n")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -\\n\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__u000b_4913" {
  let (tokens, _) = @html5.tokenize("<!-- -\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[Comment(\" -\\u{0b}\"), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3__u000c_4914" {
  let (tokens, _) = @html5.tokenize("<!-- -\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[Comment(\" -\\u{0c}\"), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3___4915" {
  let (tokens, _) = @html5.tokenize("<!-- - ")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" - \"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4916" {
  let (tokens, _) = @html5.tokenize("<!-- -!")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -!\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4917" {
  let (tokens, _) = @html5.tokenize("<!-- -\"")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -\\\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4918" {
  let (tokens, _) = @html5.tokenize("<!-- -&")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -&\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4919" {
  let (tokens, _) = @html5.tokenize("<!-- -'")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -'\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4920" {
  let (tokens, _) = @html5.tokenize("<!-- -,")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -,\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4921" {
  let (tokens, _) = @html5.tokenize("<!-- --")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" \"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4922" {
  let (tokens, _) = @html5.tokenize("<!-- -.")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -.\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4923" {
  let (tokens, _) = @html5.tokenize("<!-- -/")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -/\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__0_4924" {
  let (tokens, _) = @html5.tokenize("<!-- -0")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -0\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__1_4925" {
  let (tokens, _) = @html5.tokenize("<!-- -1")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -1\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__9_4926" {
  let (tokens, _) = @html5.tokenize("<!-- -9")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -9\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4927" {
  let (tokens, _) = @html5.tokenize("<!-- -<")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -<\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4928" {
  let (tokens, _) = @html5.tokenize("<!-- -=")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -=\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4929" {
  let (tokens, _) = @html5.tokenize("<!-- ->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" ->\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4930" {
  let (tokens, _) = @html5.tokenize("<!-- -?")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -?\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4931" {
  let (tokens, _) = @html5.tokenize("<!-- -@")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -@\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__a_4932" {
  let (tokens, _) = @html5.tokenize("<!-- -A")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -A\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__b_4933" {
  let (tokens, _) = @html5.tokenize("<!-- -B")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -B\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__y_4934" {
  let (tokens, _) = @html5.tokenize("<!-- -Y")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -Y\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__z_4935" {
  let (tokens, _) = @html5.tokenize("<!-- -Z")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -Z\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4936" {
  let (tokens, _) = @html5.tokenize("<!-- -`")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -`\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__a_4937" {
  let (tokens, _) = @html5.tokenize("<!-- -a")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -a\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__b_4938" {
  let (tokens, _) = @html5.tokenize("<!-- -b")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -b\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__y_4939" {
  let (tokens, _) = @html5.tokenize("<!-- -y")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -y\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__z_4940" {
  let (tokens, _) = @html5.tokenize("<!-- -z")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -z\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4941" {
  let (tokens, _) = @html5.tokenize("<!-- -{")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -{\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__udbc0udc00_4942" {
  let (tokens, _) = @html5.tokenize("<!-- -􀀀")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" -􀀀\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4943" {
  let (tokens, _) = @html5.tokenize("<!-- .")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" .\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4944" {
  let (tokens, _) = @html5.tokenize("<!-- /")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" /\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__0_4945" {
  let (tokens, _) = @html5.tokenize("<!-- 0")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" 0\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__1_4946" {
  let (tokens, _) = @html5.tokenize("<!-- 1")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" 1\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__9_4947" {
  let (tokens, _) = @html5.tokenize("<!-- 9")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" 9\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4948" {
  let (tokens, _) = @html5.tokenize("<!-- <")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" <\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4949" {
  let (tokens, _) = @html5.tokenize("<!-- =")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" =\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4950" {
  let (tokens, _) = @html5.tokenize("<!-- >")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" >\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4951" {
  let (tokens, _) = @html5.tokenize("<!-- ?")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" ?\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4952" {
  let (tokens, _) = @html5.tokenize("<!-- @")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" @\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__a_4953" {
  let (tokens, _) = @html5.tokenize("<!-- A")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" A\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__b_4954" {
  let (tokens, _) = @html5.tokenize("<!-- B")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" B\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__y_4955" {
  let (tokens, _) = @html5.tokenize("<!-- Y")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" Y\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__z_4956" {
  let (tokens, _) = @html5.tokenize("<!-- Z")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" Z\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4957" {
  let (tokens, _) = @html5.tokenize("<!-- `")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" `\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__a_4958" {
  let (tokens, _) = @html5.tokenize("<!-- a")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" a\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__b_4959" {
  let (tokens, _) = @html5.tokenize("<!-- b")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" b\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__y_4960" {
  let (tokens, _) = @html5.tokenize("<!-- y")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" y\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__z_4961" {
  let (tokens, _) = @html5.tokenize("<!-- z")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" z\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4962" {
  let (tokens, _) = @html5.tokenize("<!-- {")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" {\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__udbc0udc00_4963" {
  let (tokens, _) = @html5.tokenize("<!-- 􀀀")
  inspect(TokenList(tokens).to_string(), content="[Comment(\" 􀀀\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4964" {
  let (tokens, _) = @html5.tokenize("<!--!")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"!\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4965" {
  let (tokens, _) = @html5.tokenize("<!--\"")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\\\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4966" {
  let (tokens, _) = @html5.tokenize("<!--&")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"&\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4967" {
  let (tokens, _) = @html5.tokenize("<!--'")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"'\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4968" {
  let (tokens, _) = @html5.tokenize("<!--,")
  inspect(TokenList(tokens).to_string(), content="[Comment(\",\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4969" {
  let (tokens, _) = @html5.tokenize("<!---")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u0000_4970" {
  let (tokens, _) = @html5.tokenize("<!---\u{00}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-�\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u0009_4971" {
  let (tokens, _) = @html5.tokenize("<!---\t")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-\\t\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u000a_4972" {
  let (tokens, _) = @html5.tokenize("<!---\n")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-\\n\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u000b_4973" {
  let (tokens, _) = @html5.tokenize("<!---\u{0b}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-\\u{0b}\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u000c_4974" {
  let (tokens, _) = @html5.tokenize("<!---\u{0c}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-\\u{0c}\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4975" {
  let (tokens, _) = @html5.tokenize("<!--- ")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"- \"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4976" {
  let (tokens, _) = @html5.tokenize("<!---!")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-!\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4977" {
  let (tokens, _) = @html5.tokenize("<!---\"")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-\\\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4978" {
  let (tokens, _) = @html5.tokenize("<!---&")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-&\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4979" {
  let (tokens, _) = @html5.tokenize("<!---'")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-'\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4980" {
  let (tokens, _) = @html5.tokenize("<!---,")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-,\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4981" {
  let (tokens, _) = @html5.tokenize("<!----")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u0000_4982" {
  let (tokens, _) = @html5.tokenize("<!----\u{00}")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--�\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u0009_4983" {
  let (tokens, _) = @html5.tokenize("<!----\t")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--\\t\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u000a_4984" {
  let (tokens, _) = @html5.tokenize("<!----\n")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--\\n\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_u000b_4985" {
  let (tokens, _) = @html5.tokenize("<!----\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[Comment(\"--\\u{0b}\"), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_u000c_4986" {
  let (tokens, _) = @html5.tokenize("<!----\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[Comment(\"--\\u{0c}\"), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3___4987" {
  let (tokens, _) = @html5.tokenize("<!---- ")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-- \"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4988" {
  let (tokens, _) = @html5.tokenize("<!---- -")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-- \"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4989" {
  let (tokens, _) = @html5.tokenize("<!---- --")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-- \"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4990" {
  let (tokens, _) = @html5.tokenize("<!---- -->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-- \"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4991" {
  let (tokens, _) = @html5.tokenize("<!----  -->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--  \"), EOF]")
}

///|
test "html5lib/tokenizer/test3__a_4992" {
  let (tokens, _) = @html5.tokenize("<!---- a-->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-- a\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4993" {
  let (tokens, _) = @html5.tokenize("<!----!")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__4994" {
  let (tokens, _) = @html5.tokenize("<!----!>")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3___4995" {
  let (tokens, _) = @html5.tokenize("<!----! >")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--! >\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_lf_4996" {
  let (tokens, _) = @html5.tokenize("<!----!\n>")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--!\\n>\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_cr_4997" {
  let (tokens, _) = @html5.tokenize("<!----!\r>")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--!\\n>\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_crlf_4998" {
  let (tokens, _) = @html5.tokenize("<!----!\r\n>")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--!\\n>\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_a_4999" {
  let (tokens, _) = @html5.tokenize("<!----!a")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--!a\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_a_5000" {
  let (tokens, _) = @html5.tokenize("<!----!a-")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--!a\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_a_5001" {
  let (tokens, _) = @html5.tokenize("<!----!a--")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--!a\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_a_5002" {
  let (tokens, _) = @html5.tokenize("<!----!a-->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--!a\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5003" {
  let (tokens, _) = @html5.tokenize("<!----!-")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--!\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5004" {
  let (tokens, _) = @html5.tokenize("<!----!--")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--!\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5005" {
  let (tokens, _) = @html5.tokenize("<!----!-->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--!\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5006" {
  let (tokens, _) = @html5.tokenize("<!----\"")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--\\\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5007" {
  let (tokens, _) = @html5.tokenize("<!----&")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--&\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5008" {
  let (tokens, _) = @html5.tokenize("<!----'")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--'\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5009" {
  let (tokens, _) = @html5.tokenize("<!----,")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--,\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5010" {
  let (tokens, _) = @html5.tokenize("<!-----")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5011" {
  let (tokens, _) = @html5.tokenize("<!----.")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--.\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5012" {
  let (tokens, _) = @html5.tokenize("<!----/")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--/\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_0_5013" {
  let (tokens, _) = @html5.tokenize("<!----0")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--0\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_1_5014" {
  let (tokens, _) = @html5.tokenize("<!----1")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--1\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_9_5015" {
  let (tokens, _) = @html5.tokenize("<!----9")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--9\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5016" {
  let (tokens, _) = @html5.tokenize("<!----<")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--<\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5017" {
  let (tokens, _) = @html5.tokenize("<!----=")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--=\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5018" {
  let (tokens, _) = @html5.tokenize("<!---->")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5019" {
  let (tokens, _) = @html5.tokenize("<!----?")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--?\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5020" {
  let (tokens, _) = @html5.tokenize("<!----@")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--@\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_a_5021" {
  let (tokens, _) = @html5.tokenize("<!----A")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--A\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_b_5022" {
  let (tokens, _) = @html5.tokenize("<!----B")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--B\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_y_5023" {
  let (tokens, _) = @html5.tokenize("<!----Y")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--Y\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_z_5024" {
  let (tokens, _) = @html5.tokenize("<!----Z")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--Z\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5025" {
  let (tokens, _) = @html5.tokenize("<!----`")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--`\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_a_5026" {
  let (tokens, _) = @html5.tokenize("<!----a")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--a\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_b_5027" {
  let (tokens, _) = @html5.tokenize("<!----b")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--b\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_y_5028" {
  let (tokens, _) = @html5.tokenize("<!----y")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--y\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_z_5029" {
  let (tokens, _) = @html5.tokenize("<!----z")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--z\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5030" {
  let (tokens, _) = @html5.tokenize("<!----{")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--{\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_udbc0udc00_5031" {
  let (tokens, _) = @html5.tokenize("<!----􀀀")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"--􀀀\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5032" {
  let (tokens, _) = @html5.tokenize("<!---.")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-.\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5033" {
  let (tokens, _) = @html5.tokenize("<!---/")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-/\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_0_5034" {
  let (tokens, _) = @html5.tokenize("<!---0")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-0\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_1_5035" {
  let (tokens, _) = @html5.tokenize("<!---1")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-1\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_9_5036" {
  let (tokens, _) = @html5.tokenize("<!---9")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-9\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5037" {
  let (tokens, _) = @html5.tokenize("<!---<")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-<\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5038" {
  let (tokens, _) = @html5.tokenize("<!---=")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-=\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5039" {
  let (tokens, _) = @html5.tokenize("<!---?")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-?\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5040" {
  let (tokens, _) = @html5.tokenize("<!---@")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-@\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_a_5041" {
  let (tokens, _) = @html5.tokenize("<!---A")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-A\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_b_5042" {
  let (tokens, _) = @html5.tokenize("<!---B")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-B\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_y_5043" {
  let (tokens, _) = @html5.tokenize("<!---Y")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-Y\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_z_5044" {
  let (tokens, _) = @html5.tokenize("<!---Z")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-Z\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5045" {
  let (tokens, _) = @html5.tokenize("<!---`")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-`\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_a_5046" {
  let (tokens, _) = @html5.tokenize("<!---a")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-a\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_b_5047" {
  let (tokens, _) = @html5.tokenize("<!---b")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-b\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_y_5048" {
  let (tokens, _) = @html5.tokenize("<!---y")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-y\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_z_5049" {
  let (tokens, _) = @html5.tokenize("<!---z")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-z\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5050" {
  let (tokens, _) = @html5.tokenize("<!---{")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-{\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_udbc0udc00_5051" {
  let (tokens, _) = @html5.tokenize("<!---􀀀")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"-􀀀\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5052" {
  let (tokens, _) = @html5.tokenize("<!--.")
  inspect(TokenList(tokens).to_string(), content="[Comment(\".\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5053" {
  let (tokens, _) = @html5.tokenize("<!--/")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"/\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_0_5054" {
  let (tokens, _) = @html5.tokenize("<!--0")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"0\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_1_5055" {
  let (tokens, _) = @html5.tokenize("<!--1")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"1\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_9_5056" {
  let (tokens, _) = @html5.tokenize("<!--9")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"9\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5057" {
  let (tokens, _) = @html5.tokenize("<!--<")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"<\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5058" {
  let (tokens, _) = @html5.tokenize("<!--=")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"=\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5059" {
  let (tokens, _) = @html5.tokenize("<!--?")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"?\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5060" {
  let (tokens, _) = @html5.tokenize("<!--@")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"@\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_a_5061" {
  let (tokens, _) = @html5.tokenize("<!--A")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"A\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_b_5062" {
  let (tokens, _) = @html5.tokenize("<!--B")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"B\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_y_5063" {
  let (tokens, _) = @html5.tokenize("<!--Y")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"Y\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_z_5064" {
  let (tokens, _) = @html5.tokenize("<!--Z")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"Z\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5065" {
  let (tokens, _) = @html5.tokenize("<!--`")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"`\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_a_5066" {
  let (tokens, _) = @html5.tokenize("<!--a")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"a\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_b_5067" {
  let (tokens, _) = @html5.tokenize("<!--b")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"b\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_y_5068" {
  let (tokens, _) = @html5.tokenize("<!--y")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"y\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_z_5069" {
  let (tokens, _) = @html5.tokenize("<!--z")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"z\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5070" {
  let (tokens, _) = @html5.tokenize("<!--{")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"{\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_udbc0udc00_5071" {
  let (tokens, _) = @html5.tokenize("<!--􀀀")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"􀀀\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5072" {
  let (tokens, _) = @html5.tokenize("<!/")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"/\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_0_5073" {
  let (tokens, _) = @html5.tokenize("<!0")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"0\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_1_5074" {
  let (tokens, _) = @html5.tokenize("<!1")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"1\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_9_5075" {
  let (tokens, _) = @html5.tokenize("<!9")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"9\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5076" {
  let (tokens, _) = @html5.tokenize("<!<")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"<\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5077" {
  let (tokens, _) = @html5.tokenize("<!=")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"=\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5078" {
  let (tokens, _) = @html5.tokenize("<!>")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5079" {
  let (tokens, _) = @html5.tokenize("<!?")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"?\"), EOF]")
}

///|
test "html5lib/tokenizer/test3__5080" {
  let (tokens, _) = @html5.tokenize("<!@")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"@\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_a_5081" {
  let (tokens, _) = @html5.tokenize("<!A")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"A\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_b_5082" {
  let (tokens, _) = @html5.tokenize("<!B")
  inspect(TokenList(tokens).to_string(), content="[Comment(\"B\"), EOF]")
}

///|
test "html5lib/tokenizer/test3_doctype_5083" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctypeu0000_5084" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"�\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctypeu0008_5085" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE\b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"\\b\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctypeu0009_5086" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE\t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctypeu000a_5087" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctypeu000b_5088" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"\\u{0b}\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctypeu000c_5089" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctypeu000d_5090" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE\r")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctypeu001f_5091" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE\u{1f}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"\\u{1f}\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5092" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_u0000_5093" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE \u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"�\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_u0008_5094" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE \b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"\\b\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_u0009_5095" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE \t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_u000a_5096" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE \n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_u000b_5097" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE \u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"\\u{0b}\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_u000c_5098" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE \u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_u000d_5099" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE \r")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_u001f_5100" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE \u{1f}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"\\u{1f}\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5101" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE  ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5102" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE !")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"!\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5103" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE \"")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"\\\"\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5104" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE &")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"&\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5105" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE '")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"'\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5106" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE -")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"-\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5107" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE /")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"/\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_0_5108" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE 0")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"0\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_1_5109" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE 1")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"1\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_9_5110" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE 9")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"9\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5111" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE <")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"<\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5112" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE =")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"=\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5113" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE >")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=None, public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5114" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE ?")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"?\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5115" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE @")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"@\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_5116" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE A")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_b_5117" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE B")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"b\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_y_5118" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE Y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"y\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_z_5119" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE Z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"z\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5120" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE [")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"[\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype__5121" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE `")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"`\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_5122" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_au0000_5123" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a�\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_au0008_5124" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a\b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\\b\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_au0009_5125" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a\t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_au000a_5126" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_au000b_5127" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\\u{0b}\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_au000c_5128" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_au000d_5129" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a\r")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_au001f_5130" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a\u{1f}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\\u{1f}\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5131" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_u0000_5132" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a \u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_u0008_5133" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a \b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_u0009_5134" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a \t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_u000a_5135" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a \n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_u000b_5136" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a \u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_u000c_5137" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a \u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_u000d_5138" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a \r")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_u001f_5139" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a \u{1f}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5140" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a  ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5141" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a !")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5142" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a \"")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5143" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a &")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5144" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a '")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5145" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a -")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5146" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a /")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_0_5147" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a 0")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_1_5148" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a 1")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_9_5149" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a 9")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5150" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a <")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5151" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a =")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5152" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a >")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5153" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a ?")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5154" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a @")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_a_5155" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a A")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_b_5156" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a B")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5157" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu0000_5158" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu0008_5159" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu0009_5160" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000a_5161" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000b_5162" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000c_5163" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000d_5164" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\r")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu001f_5165" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\u{1f}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public__5166" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5167" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC!")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5168" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu0000_5169" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"�\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu0009_5170" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"\t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\\t\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000a_5171" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\\n\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000b_5172" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\\u{0b}\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000c_5173" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\\u{0c}\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public__5174" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\" ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\" \"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5175" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"!")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"!\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5176" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"\"")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu0000_5177" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"\"\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_u0000_5178" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"\" \u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5179" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"#")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"#\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5180" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"&")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"&\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5181" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"'")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"'\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5182" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"-")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"-\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5183" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"/")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"/\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public0_5184" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"0")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"0\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public1_5185" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"1")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"1\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public9_5186" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"9")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"9\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5187" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"<")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"<\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5188" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"=")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"=\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5189" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\">")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5190" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"?")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"?\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5191" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"@")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"@\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publica_5192" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"A")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"A\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicb_5193" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"B")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"B\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicy_5194" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"Y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"Y\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicz_5195" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"Z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"Z\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5196" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"`")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"`\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publica_5197" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"a")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"a\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicb_5198" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"b\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicy_5199" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"y\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicz_5200" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"z\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5201" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"{")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"{\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicudbc0udc00_5202" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC\"􀀀")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"􀀀\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5203" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC#")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5204" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC&")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5205" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu0000_5206" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"�\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu0009_5207" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'\t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\\t\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000a_5208" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\\n\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000b_5209" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\\u{0b}\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000c_5210" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\\u{0c}\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public__5211" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC' ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\" \"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5212" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'!")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"!\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5213" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'\"")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\\\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5214" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'&")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"&\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5215" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu0000_5216" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu0008_5217" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''\b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu0009_5218" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''\t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000a_5219" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000b_5220" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000c_5221" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu000d_5222" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''\r")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu001f_5223" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''\u{1f}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public__5224" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'' ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5225" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''!")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5226" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''\"")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5227" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''#")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5228" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''&")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5229" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'''")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicu0000_5230" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''''\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicxu0000_5231" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''''x\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_u0000_5232" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'''' \u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_xu0000_5233" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'''' x\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5234" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''(")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5235" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''-")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5236" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''/")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public0_5237" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''0")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public1_5238" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''1")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public9_5239" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''9")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5240" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''<")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5241" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''=")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5242" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5243" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''?")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5244" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''@")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publica_5245" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''A")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicb_5246" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''B")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicy_5247" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''Y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicz_5248" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''Z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5249" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''`")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publica_5250" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''a")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicb_5251" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicy_5252" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicz_5253" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5254" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''{")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicudbc0udc00_5255" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC''􀀀")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5256" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'(")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"(\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5257" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'-")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"-\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5258" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'/")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"/\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public0_5259" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'0")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"0\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public1_5260" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'1")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"1\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public9_5261" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'9")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"9\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5262" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'<")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"<\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5263" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'=")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"=\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5264" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5265" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'?")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"?\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5266" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'@")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"@\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publica_5267" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'A")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"A\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicb_5268" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'B")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"B\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicy_5269" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'Y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"Y\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicz_5270" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'Z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"Z\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5271" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'`")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"`\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publica_5272" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'a")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"a\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicb_5273" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"b\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicy_5274" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"y\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicz_5275" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"z\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5276" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'{")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"{\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicudbc0udc00_5277" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC'􀀀")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=Some(\"􀀀\"), system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5278" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC(")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5279" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC-")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5280" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC/")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public0_5281" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC0")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public1_5282" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC1")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public9_5283" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC9")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5284" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC<")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5285" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC=")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5286" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5287" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC?")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5288" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC@")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publica_5289" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLICA")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicb_5290" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLICB")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicy_5291" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLICY")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicz_5292" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLICZ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5293" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC`")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publica_5294" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLICa")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicb_5295" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLICb")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicy_5296" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLICy")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicz_5297" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLICz")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_public_5298" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC{")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_publicudbc0udc00_5299" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a PUBLIC􀀀")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5300" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu0000_5301" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_u0000_5302" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM \u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_xu0000_5303" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM \u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu0008_5304" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu0009_5305" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000a_5306" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000b_5307" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000c_5308" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000d_5309" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\r")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu001f_5310" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\u{1f}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system__5311" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5312" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM!")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5313" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu0000_5314" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"�\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu0009_5315" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"\t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\\t\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000a_5316" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\\n\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000b_5317" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\\u{0b}\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000c_5318" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\\u{0c}\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system__5319" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\" ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\" \"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5320" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"!")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"!\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5321" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"\"")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5322" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"#")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"#\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5323" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"&")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"&\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5324" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"'")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"'\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5325" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"-")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"-\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5326" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"/")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"/\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system0_5327" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"0")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"0\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system1_5328" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"1")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"1\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system9_5329" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"9")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"9\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5330" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"<")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"<\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5331" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"=")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"=\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5332" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\">")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5333" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"?")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"?\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5334" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"@")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"@\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systema_5335" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"A")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"A\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemb_5336" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"B")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"B\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemy_5337" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"Y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"Y\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemz_5338" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"Z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"Z\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5339" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"`")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"`\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systema_5340" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"a")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"a\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemb_5341" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"b\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemy_5342" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"y\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemz_5343" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"z\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5344" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"{")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"{\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemudbc0udc00_5345" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM\"􀀀")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"􀀀\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5346" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM#")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5347" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM&")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5348" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu0000_5349" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"�\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu0009_5350" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'\t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\\t\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000a_5351" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\\n\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000b_5352" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\\u{0b}\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000c_5353" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\\u{0c}\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system__5354" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM' ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\" \"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5355" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'!")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"!\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5356" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'\"")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\\\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5357" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'&")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"&\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5358" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu0000_5359" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu0008_5360" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''\b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu0009_5361" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''\t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000a_5362" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000b_5363" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000c_5364" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu000d_5365" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''\r")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemu001f_5366" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''\u{1f}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system__5367" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'' ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_u0000_5368" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'' \u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_xu0000_5369" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'' x\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5370" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''!")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5371" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''\"")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5372" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''&")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5373" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'''")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5374" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''-")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5375" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''/")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system0_5376" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''0")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system1_5377" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''1")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system9_5378" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''9")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5379" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''<")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5380" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''=")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5381" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5382" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''?")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5383" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''@")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systema_5384" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''A")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemb_5385" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''B")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemy_5386" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''Y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemz_5387" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''Z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5388" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''`")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systema_5389" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''a")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemb_5390" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemy_5391" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemz_5392" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5393" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''{")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemudbc0udc00_5394" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM''􀀀")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=false), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5395" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'(")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"(\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5396" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'-")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"-\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5397" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'/")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"/\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system0_5398" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'0")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"0\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system1_5399" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'1")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"1\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system9_5400" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'9")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"9\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5401" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'<")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"<\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5402" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'=")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"=\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5403" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5404" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'?")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"?\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5405" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'@")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"@\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systema_5406" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'A")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"A\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemb_5407" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'B")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"B\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemy_5408" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'Y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"Y\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemz_5409" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'Z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"Z\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5410" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'`")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"`\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systema_5411" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'a")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"a\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemb_5412" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'b")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"b\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemy_5413" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"y\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemz_5414" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"z\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5415" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'{")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"{\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemudbc0udc00_5416" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM'􀀀")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=Some(\"􀀀\"), force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5417" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM(")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5418" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM-")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5419" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM/")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system0_5420" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM0")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system1_5421" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM1")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system9_5422" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM9")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5423" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM<")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5424" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM=")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5425" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM>")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5426" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM?")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5427" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM@")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systema_5428" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEMA")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemb_5429" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEMB")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemy_5430" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEMY")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemz_5431" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEMZ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5432" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM`")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systema_5433" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEMa")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemb_5434" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEMb")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemy_5435" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEMy")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemz_5436" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEMz")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_system_5437" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM{")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_systemudbc0udc00_5438" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a SYSTEM􀀀")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_y_5439" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a Y")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_z_5440" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a Z")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a__5441" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a `")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_a_5442" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_au0000_5443" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a\u{00}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_au0009_5444" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a\t")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_au000a_5445" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a\n")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_au000b_5446" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a\u{0b}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_au000c_5447" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a\u{0c}")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_a__5448" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a ")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_a_5449" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a!")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_a_5450" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a\"")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_a_5451" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a&")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_a_5452" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a'")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_a_5453" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a-")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_a_5454" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a/")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_a0_5455" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a0")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_a1_5456" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a1")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}

///|
test "html5lib/tokenizer/test3_doctype_a_a9_5457" {
  let (tokens, _) = @html5.tokenize("<!DOCTYPE a a9")
  inspect(
    TokenList(tokens).to_string(),
    content="[DOCTYPE(name=Some(\"a\"), public_id=None, system_id=None, force_quirks=true), EOF]",
  )
}
