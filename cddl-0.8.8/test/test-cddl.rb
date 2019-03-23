require 'test/unit'
require 'pathname'

require 'cbor-pretty.rb'
require 'cbor-diagnostic.rb'

require_relative '../lib/cddl'
require_relative '../lib/cbor-pp'

module CDDL
  class Parser
    def validate_for_test(d, warn = true)
      validate(d, warn) && validate(d.cbor_clone, warn)
    end
  end
end

class TestABNF < Test::Unit::TestCase

  TEST_DATA_DIR = Pathname.new(__FILE__).split[0] + '../test-data'

  EXPECTED_RULES = [:type1,
 [:map,
  [:member, 1, 1, [:text, "application"], [:prim, 3]],
  [:member,
   1,
   1,
   [:text, "reputons"],
   [:array,
    [:member,
     0,
     CDDL::MANY,
     nil,
     [:map,
      [:member, 1, 1, [:text, "rater"], [:prim, 3]],
      [:member, 1, 1, [:text, "assertion"], [:prim, 3]],
      [:member, 1, 1, [:text, "rated"], [:prim, 3]],
      [:member, 1, 1, [:text, "rating"], [:prim, 7, 25]],
      [:member, 0, 1, [:text, "confidence"], [:prim, 7, 25]],
      [:member, 0, 1, [:text, "normal-rating"], [:prim, 7, 25]],
      [:member, 0, 1, [:text, "sample-size"], [:prim, 0]],
      [:member, 0, 1, [:text, "generated"], [:prim, 0]],
      [:member, 0, 1, [:text, "expires"], [:prim, 0]],
      [:member, 0, CDDL::MANY, [:prim, 3], [:prim]]]]]]]]

  def test_aa_rfc7071_concise
    parser1 = CDDL::Parser.new(File.read("#{TEST_DATA_DIR}/7071-concise.cddl"))
    assert_equal EXPECTED_RULES, parser1.rules
  end

  def test_aa_rfc7071_verbose
    parser2 = CDDL::Parser.new(File.read("#{TEST_DATA_DIR}/7071-verbose.cddl"))
    assert_equal EXPECTED_RULES, parser2.rules
    3.times do
      # puts CBOR::pretty(CBOR::encode(parser2.generate(EXPECTED_RULES)))
      puts parser2.generate.cbor_diagnostic
    end
  end

  def test_generate_hex_bin
    parser = CDDL::Parser.new <<HERE
test = [0x4711, 0xabcDEF, 0b1011001110001111000]
HERE
    assert_equal [0x4711, 0xabcDEF, 0b1011001110001111000], parser.generate
  end

  def test_generate_le
    parser = CDDL::Parser.new <<HERE
test = uint .le 10
HERE
    g = parser.generate
    p [:GLE, g]
    assert((0..10) === g)
  end

  def test_generate_ne
    parser = CDDL::Parser.new <<HERE
test = uint .ne 10
HERE
    g = parser.generate
    p [:GNE, g]
    assert_not_equal 10, g
  end

  def test_validate_person_occurs
    person = <<HERE
person = (
    name: tstr,
    age: uint,
)
HERE
    parser1 = CDDL::Parser.new "unlimitedpersons = [* person ]" + person
    parser2 = CDDL::Parser.new "oneortwoPerson = [1*2 person ]" + person
    parser3 = CDDL::Parser.new "min2Person = [2* person ]" + person

    assert parser1.validate_for_test([])
    refute parser2.validate_for_test([], false)
    refute parser3.validate_for_test([], false)
    assert parser1.validate_for_test(["Methuselah", 969])
    assert parser2.validate_for_test(["Methuselah", 969])
    refute parser3.validate_for_test(["Methuselah", 969], false)
    assert parser1.validate_for_test(["Methuselah", 969, "Methuselah", 969])
    assert parser2.validate_for_test(["Methuselah", 969, "Methuselah", 969])
    assert parser3.validate_for_test(["Methuselah", 969, "Methuselah", 969])
    assert parser1.validate_for_test(["Methuselah", 969, "Methuselah", 969, "Methuselah", 969])
    refute parser2.validate_for_test(["Methuselah", 969, "Methuselah", 969, "Methuselah", 969], false)
    assert parser3.validate_for_test(["Methuselah", 969, "Methuselah", 969, "Methuselah", 969])
    refute parser1.validate_for_test(["Methuselah", "Methuselah", 969, 969], false)
    refute parser2.validate_for_test(["Methuselah", "Methuselah", 969, 969], false)
    refute parser3.validate_for_test(["Methuselah", "Methuselah", 969, 969], false)
    refute parser1.validate_for_test(["Methuselah", "Methuselah", "Methuselah", 969, 969], false)
    refute parser2.validate_for_test(["Methuselah", "Methuselah", "Methuselah", 969, 969], false)
    refute parser3.validate_for_test(["Methuselah", "Methuselah", "Methuselah", 969, 969], false)
  end

  def test_validate
    parser1 = CDDL::Parser.new(File.read("test-data/7071-concise.cddl"))
    g = parser1.generate
    pp g
    assert parser1.validate_for_test(g)
    old = g["application"]
    g["application"] = 4711
    refute parser1.validate_for_test(g, false)
    g["application"] = old
    g["reputons"] << 5712
    refute parser1.validate_for_test(g, false)
  end

  def test_aaaaaaa_cbor_clone_hash
    a = "x".cbor_clone
    b = {a => 1}
    assert_equal 1, b[a]
    assert_equal 1, b["x".cbor_clone]
    assert_equal 1, b["x"]
    assert_equal 1, b.fetch("x".cbor_clone, :not_found)
    assert_equal 1, b.fetch("x", :not_found)
    b = {"x" => 1}.cbor_clone
    assert_equal 1, b["x"]
    assert_equal 1, b["x".cbor_clone]
    assert_equal 1, b[a]
    assert_equal 1, b.fetch("x".cbor_clone, :not_found)
    assert_equal 1, b.fetch("x", :not_found)
  end

  def test_aaaaa_validate_clone
    parser1 = CDDL::Parser.new(File.read("test-data/7071-concise.cddl"))
    g = parser1.generate
    pp g
    g = g.cbor_clone

    assert parser1.validate(g)
    old = g["application"]
    g["application"] = 4711.cbor_clone
    refute parser1.validate(g, false)
    g["application"] = old
    g["reputons"] << 5712.cbor_clone
    refute parser1.validate(g, false)
  end

  def test_validate_1
    parser = CDDL::Parser.new <<HERE
test = 1
HERE
    assert parser.validate_for_test(1)
  end

  def test_aaaaaa_validate_true
    parser = CDDL::Parser.new <<HERE
test = true
HERE
    assert parser.validate_for_test(true)
  end

  def test_validate_a
    parser = CDDL::Parser.new <<HERE
test = [* one: 1]
HERE
    assert parser.validate_for_test([])
    assert parser.validate_for_test([1])
    assert parser.validate_for_test([1, 1])
    refute parser.validate_for_test([1, 2], false)
    refute parser.validate_for_test([2, 1], false)
  end

  def test_validate_a_map
    parser = CDDL::Parser.new <<HERE
test = {* one: 1}
HERE
    assert parser.validate_for_test({})
    assert parser.validate_for_test({"one" => 1})
    refute parser.validate_for_test({"one" => 2}, false)
    refute parser.validate_for_test({"two" => 1}, false)
  end

  def test_validate_a_group_map
    parser = CDDL::Parser.new <<HERE
test = {* (text => 1)}
HERE
    assert parser.validate_for_test({})
    assert parser.validate_for_test({"one" => 1})
    refute parser.validate_for_test({"one" => 2}, false)
    assert parser.validate_for_test({"one" => 1, "two" => 1}, false)
  end

  def test_validate_a_nontrivial_group_map
    parser = CDDL::Parser.new <<HERE
test = {* (text => 1, text => 2)}
HERE
    assert parser.validate_for_test({})
    assert parser.validate_for_test({"one" => 2, "two" => 1})
    assert parser.validate_for_test({"one" => 1, "two" => 2})
    refute parser.validate_for_test({"one" => 1}, false)
    assert parser.validate_for_test({"one" => 1, "two" => 2, "uno" => 1, "due" => 2})
  end


  def test_murray
    parser = CDDL::Parser.new <<HERE
a = {
  b
}

b = (
  (x: int // y: int), z: int
)
HERE
    assert parser.validate_for_test({})
    assert parser.validate_for_test({"x" => 2, "z" => 1})
    assert parser.validate_for_test({"y" => 1, "z" => 2})
    refute parser.validate_for_test({"z" => 1}, false)
    assert parser.validate_for_test({"one" => 1, "two" => 2, "uno" => 1, "due" => 2})
  end


  def test_murray_workaround
    parser = CDDL::Parser.new <<HERE
a = {
  b
}

b = ( z: int
  (x: int // y: int)
)
HERE
    assert parser.validate_for_test({})
    assert parser.validate_for_test({"x" => 2, "z" => 1})
    assert parser.validate_for_test({"y" => 1, "z" => 2})
    refute parser.validate_for_test({"z" => 1}, false)
    assert parser.validate_for_test({"one" => 1, "two" => 2, "uno" => 1, "due" => 2})
  end


  def test_validate_a_string
    parser = CDDL::Parser.new <<HERE
test = [* one: "one"]
HERE
    assert parser.validate_for_test([])
    assert parser.validate_for_test(["one"])
    assert parser.validate_for_test(["one", "one"])
    refute parser.validate_for_test([1], false)
    refute parser.validate_for_test(['two'], false)
    refute parser.validate_for_test(["one", "two"], false)
  end


  def test_validate_a_string_string
    parser = CDDL::Parser.new <<HERE
test = [* "two" => "one"]
HERE
    assert parser.validate_for_test([])
    assert parser.validate_for_test(["one"])
    assert parser.validate_for_test(["one", "one"])
    refute parser.validate_for_test([1], false)
    refute parser.validate_for_test(['two'], false)
    refute parser.validate_for_test(["one", "two"], false)
  end

  def test_validate_a_once
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test = [1]
HERE
    # puts "RULES:"
    # pp parser.rules
    # puts "APR:"
    # pp parser.apr
    refute parser.validate_for_test([], false)
    assert parser.validate_for_test([1])
    refute parser.validate_for_test([1, 1], false)
    refute parser.validate_for_test([1, 2], false)
    refute parser.validate_for_test([2, 1], false)
  end

  def test_validate_unknown_key
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test = { 1, 2 }
HERE
    # puts "RULES:"
    assert_raise {  # TODO: This really should be checked at parse time
      pp parser.rules
    }
    # puts "APR:"
    # pp parser.apr
    assert_raise { puts parser.generate() }
    assert_raise { parser.validate({}) }
  end

  def test_validate_not_unknown_key
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test = [ 1, 2 ]
HERE
    # puts "RULES:"
    # pp parser.rules
    # puts "APR:"
    # pp parser.apr
    assert_equal [1, 2], parser.generate()
    refute parser.validate_for_test({}, false)
    refute parser.validate_for_test([], false)
    refute parser.validate_for_test([1], false)
    assert parser.validate_for_test([1, 2])
  end


  def test_validate_not_unknown_key_paren
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test = [ (1, 2) ]
HERE
    # puts "RULES:"
    # pp parser.rules
    # puts "APR:"
    # pp parser.apr
    assert_equal [1, 2], parser.generate()
    refute parser.validate_for_test({}, false)
    refute parser.validate_for_test([], false)
    refute parser.validate_for_test([1], false)
    assert parser.validate_for_test([1, 2])
  end


  def test_validate_alternate3  # XXX need indirection for now
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test = [* test1]
test1 = (one: 1, two: 2)
HERE
    # puts "RULES:"
    # pp parser.rules
    # puts "APR:"
    # pp parser.apr
    assert parser.validate_for_test([])
    assert parser.validate_for_test([1, 2])
    assert parser.validate_for_test([1, 2, 1, 2])
    refute parser.validate_for_test([1, 1, 2, 2], false)
    refute parser.validate_for_test([1], false)
    refute parser.validate_for_test([1, 2, 1], false)
  end

  def test_validate_occur1  # XXX need indirection for now
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test = [test1]
test1 = (one: 1, two: 2)
HERE
    # puts "RULES:"
    # pp parser.rules
    # puts "APR:"
    # pp parser.apr
    refute parser.validate_for_test([], false)
    refute parser.validate_for_test([1], false)
    assert parser.validate_for_test([1, 2])
    refute parser.validate_for_test([2, 1], false)
    refute parser.validate_for_test([1, 1, 2, 2], false)
    refute parser.validate_for_test([1, 2, 1, 2], false)
    refute parser.validate_for_test([1, 2, 1], false)
  end

  def test_validate_occur01  # XXX need indirection for now
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test = [? test1]
test1 = (one: 1, two: 2)
HERE
    # puts "RULES:"
    # pp parser.rules
    # puts "APR:"
    # pp parser.apr
    assert parser.validate_for_test([])
    refute parser.validate_for_test([1], false)
    assert parser.validate_for_test([1, 2])
    refute parser.validate_for_test([2, 1], false)
    refute parser.validate_for_test([1, 1, 2, 2], false)
    refute parser.validate_for_test([1, 2, 1, 2], false)
    refute parser.validate_for_test([1, 2, 1], false)
  end

  def test_validate_occur1n  # XXX need indirection for now
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test = [+ test1]
test1 = (one: 1, two: 2)
HERE
    # puts "RULES:"
    # pp parser.rules
    # puts "APR:"
    # pp parser.apr
    refute parser.validate_for_test([], false)
    refute parser.validate_for_test([1], false)
    assert parser.validate_for_test([1, 2])
    refute parser.validate_for_test([2, 1], false)
    refute parser.validate_for_test([1, 1, 2, 2], false)
    assert parser.validate_for_test([1, 2, 1, 2])
    refute parser.validate_for_test([1, 2, 1], false)
  end

  def test_validate_occur0n  # XXX need indirection for now
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test = [* test1]
test1 = (one: 1, two: 2)
HERE
    # puts "RULES:"
    # pp parser.rules
    # puts "APR:"
    # pp parser.apr
    assert parser.validate_for_test([])
    refute parser.validate_for_test([1], false)
    assert parser.validate_for_test([1, 2])
    refute parser.validate_for_test([2, 1], false)
    refute parser.validate_for_test([1, 1, 2, 2], false)
    assert parser.validate_for_test([1, 2, 1, 2])
    refute parser.validate_for_test([1, 2, 1], false)
  end


  def test_validate_occur23  # XXX need indirection for now
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test = [2*3 test1]
test1 = (one: 1, two: 2)
HERE
    # puts "RULES:"
    # pp parser.rules
    # puts "APR:"
    # pp parser.apr
    assert_includes [[1, 2, 1, 2], [1, 2, 1, 2, 1, 2]], parser.generate
    refute parser.validate_for_test([], false)
    refute parser.validate_for_test([1], false)
    refute parser.validate_for_test([1, 2], false)
    refute parser.validate_for_test([2, 1], false)
    assert parser.validate_for_test([1, 2, 1, 2])
    assert parser.validate_for_test([1, 2, 1, 2, 1, 2])
    refute parser.validate_for_test([1, 2, 1, 2, 1, 2, 1, 2], false)
    refute parser.validate_for_test([1, 1, 2, 2, 2], false)
    refute parser.validate_for_test([1, 1, 1, 2, 2, 2], false)
    refute parser.validate_for_test([1, 2, 1], false)
  end


  def test_validate_occur12plus1  # XXX need indirection for now
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test = [1*2 test1 1*1 test1]
test1 = (one: 1, two: 2)
HERE
    # puts "RULES:"
    # pp parser.rules
    # puts "APR:"
    # pp parser.apr
    assert_includes [[1, 2, 1, 2], [1, 2, 1, 2, 1, 2]], parser.generate
    refute parser.validate_for_test([], false)
    refute parser.validate_for_test([1], false)
    refute parser.validate_for_test([1, 2], false)
    refute parser.validate_for_test([2, 1], false)
    refute parser.validate_for_test([1, 2, 1, 2], false) # !!! PEG semantics gets us here
    assert parser.validate_for_test([1, 2, 1, 2, 1, 2])
    refute parser.validate_for_test([1, 2, 1, 2, 1, 2, 1, 2], false)
    refute parser.validate_for_test([1, 1, 2, 2, 2], false)
    refute parser.validate_for_test([1, 1, 1, 2, 2, 2], false)
    refute parser.validate_for_test([1, 2, 1], false)
  end


  def test_generate_occur2  # XXX need indirection for now
    parser = CDDL::Parser.new <<HERE
test = [2*2 test1 1*1 test1]
test1 = (one: 1, two: 2)
HERE
    assert_equal [1, 2, 1, 2, 1, 2], parser.generate
  end

  def test_generate_occur3  # XXX need indirection for now
    parser = CDDL::Parser.new <<HERE
test = [5*5 "foo"]
HERE
    assert_equal Array.new(5, "foo"), parser.generate
  end

  def test_basic_string  # XXX need indirection for now
    parser = CDDL::Parser.new <<HERE
test = "foo"
HERE
    assert_equal "foo", parser.generate
  end


  def test_simple_alternative
    parser = CDDL::Parser.new <<HERE
test = {
  foo: 1
  bar: 1 / 2
  baz: 3
  bee: 4
}
HERE
    # pp parser.rules
    expected1 = {'foo' => 1, 'bar' => 1, 'baz' => 3, 'bee' => 4}
    expected2 = {'foo' => 1, 'bar' => 2, 'baz' => 3, 'bee' => 4}
    10.times {
      g = parser.generate
      # pp g
      assert expected1 == g || expected2 == g
      assert parser.validate_for_test(g)
    }
  end

  def test_another_simple_alternative
    parser = CDDL::Parser.new <<HERE
test = {
  bar: int / true
}
HERE
    # pp parser.rules
    10.times {
      g = parser.generate
      # pp ["tasa", g]
      bar = g['bar']
      assert bar == true || Integer(bar)
      assert parser.validate_for_test(g)
    }
  end

  def test_another_simple_alternative_group
    parser = CDDL::Parser.new <<HERE
test = {
  bar: int // bar: true
}
HERE
    # pp parser.rules
    10.times {
      g = parser.generate
      # pp ["tasag", g]
      bar = g['bar']
      assert bar == true || Integer(bar)
      assert parser.validate_for_test(g)
      refute parser.validate_for_test(g.merge(foo: 3), false)
      refute parser.validate_for_test(g.merge(bar: "baz"), false)
    }
  end

  def test_another_simple_alternative_group_occur
    parser = CDDL::Parser.new <<HERE
test = {
  ?(bar: int // bar: true)
}
HERE
    # pp parser.rules
    parser.validate_for_test({})
    10.times {
      g = parser.generate
      # pp ["tasag", g]
      if g != {}
        bar = g['bar']
        fail "GGG #{g.inspect}" unless bar
        assert bar == true || Integer(bar)
        assert parser.validate_for_test(g)
        refute parser.validate_for_test(g.merge(foo: 3), false)
        refute parser.validate_for_test(g.merge(bar: "baz"), false)
      end
    }
  end

  def test_bad_simple_alternative_group
    parser = CDDL::Parser.new <<HERE
test = {
  bar: int // true              ; no member key in second choice
}
HERE
    assert_raise { parser.rules }
  end


  def test_simple_alternative_in_array
    parser = CDDL::Parser.new <<HERE
test = [
  1 / 2
  3 / 4
]
HERE
    # pp parser.rules
    10.times {
      g = parser.generate
      #pp ["saia", g]
      assert_equal g.size, 2
      assert [1, 2].include? g[0]
      assert [3, 4].include? g[1]
      assert parser.validate_for_test(g)
    }
  end

  def test_simple_alternative_in_array2
    parser = CDDL::Parser.new <<HERE
test = [
  1 / 2
  bar
  foob: 3 / 4
]
bar = 5 / 6
HERE
    # pp parser.rules
    10.times {
      g = parser.generate
      # pp ["saia", g]
      assert_equal g.size, 3
      assert [1, 2].include? g[0]
      assert [5, 6].include? g[1]
      assert [3, 4].include? g[2]
      assert parser.validate_for_test(g)
    }
  end


  def test_group_choice_in_array2
    parser = CDDL::Parser.new <<HERE
test = [
  (1 // 2)
  bar
  (foob: 3 // boof: 4)
  (bar // zab: 9, baz: 10)
]
bar = (5 // 6)
HERE
    # puts parser.ast_debug
    # pp parser.rules
    10.times {
      g = parser.generate
      pp ["gcia", g]
      assert_equal g.size, (g[3] == 9 ? 5 : 4)
      assert [1, 2].include? g[0]
      assert [5, 6].include? g[1]
      assert [3, 4].include? g[2]
      assert [5, 6, 9].include? g[3]
      assert_equal g[4], 10 if g[3] == 9
      assert parser.validate_for_test(g)
    }
    refute parser.validate_for_test([1, 5, 8, 9], false)
    refute parser.validate_for_test([1, 5, 3], false)
    assert parser.validate_for_test([1, 5, 4, 5])
    refute parser.validate_for_test([1, 5, 4, 9], false)
    assert parser.validate_for_test([1, 5, 4, 9, 10])
    refute parser.validate_for_test([1, 5, 4, 3], false)
    refute parser.validate_for_test([1, 5, 4, 9, 10, 3], false)
  end

  def test_aaaa_validate_number
    parser = CDDL::Parser.new <<HERE
test = number
HERE
    # pp parser.rules
    assert parser.validate_for_test(1)
    assert parser.validate_for_test(1.2)
  end

  def test_aaaa_validate_number_le
    parser = CDDL::Parser.new <<HERE
test = number .le 2
HERE
    # pp parser.rules
    assert parser.validate_for_test(1)
    assert parser.validate_for_test(1.2)
    assert parser.validate_for_test(2)
    assert parser.validate_for_test(2.0)
    refute parser.validate_for_test(2.1, false)
  end

  def test_aaaa_validate_number_lt
    parser = CDDL::Parser.new <<HERE
test = number .lt 2
HERE
    # pp parser.rules
    assert parser.validate_for_test(1)
    assert parser.validate_for_test(1.2)
    refute parser.validate_for_test(2, false)
    refute parser.validate_for_test(2.0, false)
    refute parser.validate_for_test(2.1, false)
  end

  def test_aaaa_validate_number_ne
    parser = CDDL::Parser.new <<HERE
test = number .ne 2
HERE
    # pp parser.rules
    assert parser.validate_for_test(1)
    assert parser.validate_for_test(1.2)
    refute parser.validate_for_test(2, false)
    refute parser.validate_for_test(2.0, false)
    assert parser.validate_for_test(2.1)
  end

  def test_aaaa_validate_number_default
    parser = CDDL::Parser.new <<HERE
test = number .default 2
HERE
    # pp parser.rules
    assert parser.validate_for_test(1)
    assert parser.validate_for_test(1.2)
    assert parser.validate_for_test(2)
    assert parser.validate_for_test(2.0)
    assert parser.validate_for_test(2.1)
  end

  def test_aaaa_validate_number_eq
    parser = CDDL::Parser.new <<HERE
test = number .eq 2
HERE
    # pp parser.rules
    refute parser.validate_for_test(1, false)
    refute parser.validate_for_test(1.2, false)
    assert parser.validate_for_test(2)
    assert parser.validate_for_test(2.0)
    refute parser.validate_for_test(2.1, false)
  end


  def test_aaaa_validate_string_eq
    parser = CDDL::Parser.new <<HERE
test = (text/bytes) .eq "foo"
HERE
    # pp parser.rules
    refute parser.validate_for_test(1, false)
    assert parser.validate_for_test("foo")
    assert parser.validate_for_test("foo".b) #  XXX Feature!
    refute parser.validate_for_test("bar", false)
  end

  def test_validate_number_key
    parser = CDDL::Parser.new <<HERE
test = [test1, test2, test3]
test1 = {1: 2}
test2 = {3.0 => "a"}
test3 = {foo: "bar"}
HERE
    # pp parser.rules
    expected = [{1 => 2}, {3.0 => "a"}, {'foo' => "bar"}]
    assert_equal expected, parser.generate
    assert parser.validate_for_test(expected)
  end

  def test_validate_json_float
    parser = CDDL::Parser.new <<HERE
test = {
foo: int
? bar: beer
f16: float16
? "f32": float32
? 1: float32
"f64" => float64
}
beer = 3.14 / 6.28
HERE
    # pp parser.rules
    # pp parser.generate
    refute parser.validate_for_test({}, false)
    assert parser.validate_for_test({"f16" => 1.5, "foo" => 1, "f64" => 1.1, "bar" => 3.14})
    assert parser.validate_for_test({"f16" => 1.5, "foo" => 1, "f64" => 1.1, "bar" => 6.28})
    refute parser.validate_for_test({"f16" => 1.5, "foo" => 1, "f64" => 1.1, "bar" => 3.15}, false)
    assert parser.validate_for_test({"f16" => 1.5, "foo" => 1, "f64" => 1.1})
    refute parser.validate_for_test({"f16" => 1, "foo" => 1, "f64" => 1.1}, false)
  end

  def test_validate_tags
    parser = CDDL::Parser.new <<HERE
my_breakfast = #6.55799(breakfast)   ; cbor-any is too general!
breakfast = cereal / porridge
cereal = #6.998(tstr)
porridge = #6.999([liquid, solid])
liquid = milk / water
milk = 0
water = 1
solid = tstr
HERE
    # pp parser.rules
    # pp parser.generate
    refute parser.validate_for_test({}, false)
    refute parser.validate_for_test(CBOR::Tagged.new(55799, CBOR::Tagged.new(997, 1)), false)
    refute parser.validate_for_test(CBOR::Tagged.new(55799, CBOR::Tagged.new(998, 1)), false)
    assert parser.validate_for_test(CBOR::Tagged.new(55799, CBOR::Tagged.new(998, "cornflakes")))
    assert parser.validate_for_test(CBOR::Tagged.new(55799, CBOR::Tagged.new(999, [0, "barley"])))
    refute parser.validate_for_test(CBOR::Tagged.new(55799, CBOR::Tagged.new(999, [0, 1])), false)
    refute parser.validate_for_test(CBOR::Tagged.new(55799, CBOR::Tagged.new(999, [0, "barley", 1])), false)
  end

  def test_nested_group_many1
    parser = CDDL::Parser.new <<HERE
foo = {* bar}
bar = (* b: 1)
HERE
    assert_equal [:type1, [:map, [:member, 0, CDDL::MANY, [:text, "b"], [:int, 1]]]], parser.rules
  end

  def test_nested_group_many2
    parser = CDDL::Parser.new <<HERE
foo = {* bar}
bar = (b: 1)
HERE
    assert_equal [:type1, [:map, [:member, 0, CDDL::MANY, [:text, "b"], [:int, 1]]]], parser.rules
  end

  def test_nested_group_many3
    parser = CDDL::Parser.new <<HERE
foo = {* bar}
bar = (4*6 b: 1)
HERE
    assert_equal [:type1, [:map, [:member, 0, CDDL::MANY, [:text, "b"], [:int, 1]]]], parser.rules
  end

  def test_range_integer
    parser = CDDL::Parser.new <<HERE
color = 0..12
HERE
    pp parser.generate
    10.times {
      assert parser.generate.between?(0, 12)
    }
    assert parser.validate_for_test(0)
    assert parser.validate_for_test(7)
    assert parser.validate_for_test(12)
    refute parser.validate_for_test(-1, false)
    refute parser.validate_for_test(13, false)
  end

  def test_range_integer_excl
    parser = CDDL::Parser.new <<HERE
color = 0...13
HERE
    10.times {
      assert parser.generate.between?(0, 12)
    }
    assert parser.validate_for_test(0)
    assert parser.validate_for_test(7)
    refute parser.validate_for_test(7.0, false)
    assert parser.validate_for_test(12)
    refute parser.validate_for_test(-1, false)
    refute parser.validate_for_test(13, false)
  end

  def test_range_float
    parser = CDDL::Parser.new <<HERE
color = 0.5..max
max = 12.5
HERE
    # pp parser.rules
    10.times {
      assert parser.generate.between?(0.5, 12.5)
    }
    refute parser.validate_for_test(0.0, false)
    assert parser.validate_for_test(0.5)
    assert parser.validate_for_test(7.0)
    refute parser.validate_for_test(7, false)
    assert parser.validate_for_test(12.0)
    assert parser.validate_for_test(12.5)
    refute parser.validate_for_test(-1.0, false)
    refute parser.validate_for_test(13.0, false)
  end

  def test_enum
    parser = CDDL::Parser.new <<HERE
color = &(
  black: 0,
  red: 1,
  green: 2,
  yellow: 3,
  blue: 4,
  magenta: 5,
  cyan: 6,
  white: 7,
  orange: 8,
  pink: 9,
  purple: 10,
  brown: 11,
  grey: 12,
)
HERE
    # brittle on type1 nesting optimization
    assert_equal [:type1,
                  [:type1,
                   [:int, 0],
                   [:int, 1],
                   [:int, 2],
                   [:int, 3],
                   [:int, 4],
                   [:int, 5],
                   [:int, 6],
                   [:int, 7],
                   [:int, 8],
                   [:int, 9],
                   [:int, 10],
                   [:int, 11],
                   [:int, 12]]], parser.rules
    10.times {
      assert parser.generate.between?(0, 12)
    }
  end

  def test_enum_indirect
    parser = CDDL::Parser.new <<HERE
color = &colors
basecolors = (
  red: 1,
  green: 2,
  blue: 4,
  lila,
)
lila = (
  magenta: 5,
  pink: 9,
  purple: 10,
)
colors = (
  black: 0,
  basecolors,
  yellow: 3,
  cyan: 6,
  white: 7,
  orange: 8,
  brown: 11,
  grey: 12,
)
HERE
    # brittle on type1 nesting optimization
    assert_equal [:type1,
                  [:type1,
                   [:int, 0],
                   [:int, 1],
                   [:int, 2],
                   [:int, 4],
                   [:int, 5],
                   [:int, 9],
                   [:int, 10],
                   [:int, 3],
                   [:int, 6],
                   [:int, 7],
                   [:int, 8],
                   [:int, 11],
                   [:int, 12]]], parser.rules
    10.times {
      assert parser.generate.between?(0, 12)
    }
  end

  def test_invalidate_unequal_range
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test =  1..2.5
HERE
    # puts "RULES:"
    assert_raise {  # TODO: This really should be checked at parse time
      pp parser.rules
    }
    # puts "APR:"
    # pp parser.apr
    assert_raise { puts parser.generate() }
    assert_raise { parser.validate({}) }
  end

  def test_invalidate_boolean_range
    # $debug_ast = true
    parser = CDDL::Parser.new <<HERE
test = false..true
HERE
    # puts "RULES:"
    assert_raise {  # TODO: This really should be checked at parse time
      pp parser.rules
    }
    # puts "APR:"
    # pp parser.apr
    assert_raise { puts parser.generate() }
    assert_raise { parser.validate({}) }
  end

  def test_identical_redefinition
    parser = CDDL::Parser.new <<HERE
test =
  "Cephalotaxus Germanism dovekey Istiophorus" / foo
test = "Cephalotaxus Germanism dovekey Istiophorus"
/ foo
foo = 1
HERE
    pp parser.rules
  end

  def test_bad_redefinition
    parser = CDDL::Parser.new <<HERE
test =
  "Cephalotaxus Germanism dovekey Istiophorus" / foo
test = "Cephalotaxus Germanism dovekey Istiophorus"
/ fob
foo = 1
fob = 1
HERE
    assert_raise {
      pp parser.rules
    }
  end

  def test_bad_annotation
    parser = CDDL::Parser.new <<HERE
test = int .foo 3
HERE
    assert_raise {
      pp parser.rules
    }
  end

  def test_size_annotation
    parser = CDDL::Parser.new <<HERE
test = bstr .size 3
HERE
    pp parser.rules
    gen = parser.generate
    assert String === gen
    assert gen.bytesize == 3
    pp gen
    assert parser.validate_for_test(gen)
  end


  def test_uint_size_annotation
    parser = CDDL::Parser.new <<HERE
test = uint .size 3
HERE
    pp parser.rules
    10.times do
      gen = parser.generate
      assert Integer === gen
      assert gen < 2**24
      assert gen >= 0
      assert parser.validate_for_test(gen)
    end
    refute parser.validate_for_test(-1, false)
    refute parser.validate_for_test(2**24, false)
    refute parser.validate_for_test(2**218, false)
  end

  def test_bits_annotation
    parser = CDDL::Parser.new <<HERE
test = bstr .bits (1 / 3 / 5)
HERE
    # pp parser.rules
    gen = parser.generate
    assert String === gen
    pp gen                      # should mostly be "*"
    assert parser.validate_for_test(gen)
    assert parser.validate_for_test("\x08".b)
    refute parser.validate_for_test("\x01".b, false)
    refute parser.validate_for_test("\x10".b, false)
    refute parser.validate_for_test("\x40".b, false)
  end

  def test_bits_annotation_on_uint
    parser = CDDL::Parser.new <<HERE
test = uint .bits (1 / 3 / 5)
HERE
    # pp parser.rules
    gen = parser.generate
    assert Integer === gen
    pp gen                      # should mostly be 42
    assert parser.validate_for_test(gen)
    assert parser.validate_for_test(1 << 3)
    refute parser.validate_for_test(1 << 0, false)
    refute parser.validate_for_test(1 << 4, false)
    refute parser.validate_for_test(1 << 6, false)
  end

  def test_regexp_annotation
    parser = CDDL::Parser.new <<HERE
test = tstr .regexp "reg.*"
HERE
    pp parser.rules
    5.times do
      gen = parser.generate
      assert String === gen
      pp gen
      assert parser.validate_for_test(gen)
    end
    assert parser.validate_for_test("reg")
    assert parser.validate_for_test("regfoo")
    refute parser.validate_for_test("foo", false)
    refute parser.validate_for_test("re", false)
  end

  def test_cbor_annotation1
    parser = CDDL::Parser.new <<HERE
test = bytes .cbor 1
HERE
    pp parser.rules
    5.times do
      gen = parser.generate
      assert_equal "\x01", gen
      pp gen
      assert parser.validate_for_test(gen)
    end
    assert parser.validate_for_test("\x01".b)
    assert parser.validate_for_test("\x18\x01".b)
    refute parser.validate_for_test("1", false)
    refute parser.validate_for_test("\x00".b, false)
  end

  def test_cbor_annotation_uint
    parser = CDDL::Parser.new <<HERE
test = bytes .cbor uint
HERE
    pp parser.rules
    5.times do
      gen = parser.generate
      assert String === gen
      assert_equal 0, gen.getbyte(0) >> 5
      pp ["CAU", gen]
      assert parser.validate_for_test(gen)
    end
    assert parser.validate_for_test("\x01".b)
    assert parser.validate_for_test("\x00".b)
    assert parser.validate_for_test("\x18\x01".b)
    refute parser.validate_for_test("1", false)
    refute parser.validate_for_test("\x00\x00".b, false)
  end

  def test_cborseq_annotation_uint
    parser = CDDL::Parser.new <<HERE
test = bytes .cborseq uint
HERE
    assert_raise {
      parser.generate
    }
  end

def test_cbor_annotation_uint_array
    parser = CDDL::Parser.new <<HERE
test = bytes .cborseq myarray
myarray = [1*4uint]
HERE
    pp parser.rules
    5.times do
      gen = parser.generate
      assert String === gen
      pp ["CAUA", gen]
      assert_equal 0, gen.getbyte(0) >> 5 unless gen == ''
      assert parser.validate_for_test(gen)
    end
    assert parser.validate_for_test("\x01".b)
    assert parser.validate_for_test("\x18\x01".b)
    refute parser.validate_for_test("1", false)
    refute parser.validate_for_test("\x00\x00\x00\x00\x00".b, false)
end

def test_and_annotation
    parser = CDDL::Parser.new <<HERE
test = mtype .and uint
mtype = 1/2/3/4/-1
HERE
    pp parser.rules
    5.times do
      gen = parser.generate
      assert Integer === gen
      pp ["CAA", gen]
      assert parser.validate_for_test(gen)
    end
    assert parser.validate_for_test(1)
    refute parser.validate_for_test(-1, false)
    refute parser.validate_for_test(0, false)
end

def test_within_annotation
    parser = CDDL::Parser.new <<HERE
test = mtype .within uint
mtype = 1/2/3/4/-1
HERE
    pp parser.rules
    20.times do
      gen = parser.generate
      assert Integer === gen
      pp ["CWA", gen]           # should also generate some warnings
      assert parser.validate_for_test(gen)
    end
    assert parser.validate_for_test(1)
    refute parser.validate_for_test(-1, false)
    refute parser.validate_for_test(0, false)
end

  def test_dcaf
    parser1 = CDDL::Parser.new(File.read("#{TEST_DATA_DIR}/dcaf1.cddl"))
    # assert_equal EXPECTED_RULES, parser1.rules
    pp parser1.generate
  end


  def test_generic1
    parser = CDDL::Parser.new <<HERE
d = a<1>
a<b> = b
HERE
    assert_equal 1, parser.generate
  end

  def test_generic_group
    parser = CDDL::Parser.new <<HERE
d = a<mygr>
a<gr> = { gr }
mygr = (
1 => 2
)
HERE
    assert_equal({1 => 2}, parser.generate)
  end

  def test_generic_transitive
    parser = CDDL::Parser.new <<HERE
d = a<mygr>
a<gr> = { b<gr> }
b<foo> = foo
mygr = (
1 => 2
)
HERE
    assert_equal({1 => 2}, parser.generate)
  end

  def test_generic_realistic
    parser = CDDL::Parser.new <<HERE
start = [request, response]
request = message<0>
response = message<1>
message<code> = {
  code: code
  data: "hallo data"
}
HERE
    assert_equal([{"code"=>0, "data"=>"hallo data"},
                  {"code"=>1, "data"=>"hallo data"}], parser.generate)
  end

  def test_generic_enum
    parser = CDDL::Parser.new <<HERE
color<foo> = &foo
color = color<colors>
basecolors = (
  red: 1,
  green: 2,
  blue: 4,
  lila,
)
lila = (
  magenta: 5,
  pink: 9,
  purple: 10,
)
colors = (
  black: 0,
  basecolors,
  yellow: 3,
  cyan: 6,
  white: 7,
  orange: 8,
  brown: 11,
  grey: 12,
)
HERE
    # brittle on type1 nesting optimization
    assert_equal [:type1,
                  [:type1,
                   [:int, 0],
                   [:int, 1],
                   [:int, 2],
                   [:int, 4],
                   [:int, 5],
                   [:int, 9],
                   [:int, 10],
                   [:int, 3],
                   [:int, 6],
                   [:int, 7],
                   [:int, 8],
                   [:int, 11],
                   [:int, 12]]], parser.rules
    10.times {
      assert parser.generate.between?(0, 12)
    }
  end

  def test_endless_recursion
    parser = CDDL::Parser.new <<HERE
a = a
HERE
    assert_raise { parser.validate(1) }
    assert_raise { parser.generate }
  end

  def test_recursion
    parser = CDDL::Parser.new <<HERE
a = [a] / 1
HERE
    10.times {
      g = parser.generate
      # pp ["recurse-test1", g]
      assert parser.validate_for_test(g)
    }
  end

  def test_endless_group_recursion
    parser = CDDL::Parser.new <<HERE
b = {a}
a = (
  foo: int
  a
)
HERE
    assert_raise { parser.validate(1) }
    assert_raise { parser.generate }
  end

  def test_non_group_recursion
    parser = CDDL::Parser.new <<HERE
a = {
  foo: int
  bar: ([a] / 1)
}
HERE
    10.times {
      g = parser.generate
      # pp ["non-recurse-test", g]
      assert parser.validate_for_test(g)
    }
  end

  def test_group_recursion
    parser = CDDL::Parser.new <<HERE
b = {a}
a = (
  foo: int
  bar: ([a] / 1)
)
HERE
    p parser.rules
    10.times {
      g = parser.generate
      pp ["recurse-group-test", g]
      assert parser.validate_for_test(g)
    }
  end


  def test_group_recursion2
    parser = CDDL::Parser.new <<HERE
b = {1: 2, a}
a = (
  foo: int
  bar: ([+aa] / 1 / 2)
)
aa = {a}
HERE
    p parser.rules
    10.times {
      g = parser.generate
      # pp ["recurse-group-test2", g]
      assert parser.validate_for_test(g)
      refute parser.validate_for_test(g.merge(baz: 3), false)
    }
  end

  
  def test_group_recursion_fail1
    parser = CDDL::Parser.new <<HERE
b = {a}
a = (
  foo: int
  bar: ([a: a] / 1)
)
HERE
    assert_raise { p parser.rules }
  end

  def test_empty_group
    parser = CDDL::Parser.new <<HERE
a = {b}
b = ()
HERE
    # puts "empty_group AST:"
    # puts parser.ast_debug
    # puts "empty_group RULES:"
    # pp parser.rules
    assert_equal({}, parser.generate)
    assert parser.validate_for_test({})
  end


  def test_empty_group_sp
    parser = CDDL::Parser.new <<HERE
a = {b}
b = (
)
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "empty_group_sp RULES:"
    # pp parser.rules
    assert_equal({}, parser.generate)
    assert parser.validate_for_test({})
  end


  def test_empty_group_augmented
    parser = CDDL::Parser.new <<HERE
a = {b}
b = (
)
; b //= (3)   PENDING: need to recognize this as group
b //= ()
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "empty_group_sp RULES:"
    # pp parser.rules
    assert_equal({}, parser.generate)
    assert parser.validate_for_test({})
  end

  def test_simple_group_augmented
    parser = CDDL::Parser.new <<HERE
a = {b}
b = ( "abs": 3 )
; b //= (3)   PENDING: need to recognize this as group
b //= ( "abs": -3 )
b //= ( "abs": 5 )
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "simple_group_augmented RULES:"
    # pp parser.rules
    assert_equal(["abs"], parser.generate.keys)
    v = {}
    20.times do
      v[parser.generate["abs"]] = true
    end
    assert_equal({3 => true, -3 => true, 5 => true}, v)
    assert parser.validate_for_test({"abs" => 3})
    assert parser.validate_for_test({"abs" => 5})
    assert parser.validate_for_test({"abs" => -3})
  end

  def test_simple_group_augmented_uninitialized
    parser = CDDL::Parser.new <<HERE
a = {b}
b //= ( "abs": 3 )
; b //= (3)   PENDING: need to recognize this as group
b //= ( "abs": -3 )
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "simple_group_augmented_uninitialized RULES:"
    # pp parser.rules
    assert_equal(["abs"], parser.generate.keys)
    v = {}
    10.times do
      v[parser.generate["abs"]] = true
    end
    assert_equal({3 => true, -3 => true}, v)
    assert parser.validate_for_test({"abs" => 3})
    assert parser.validate_for_test({"abs" => -3})
  end


  def test_simple_type_augmented
    parser = CDDL::Parser.new <<HERE
a = {b}
b = ( "abs": t1 )
t1 = 3
t1 /= -3
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "simple_type_augmented RULES:"
    # pp parser.rules
    assert_equal(["abs"], parser.generate.keys)
    v = {}
    20.times do                 # OK, this is probabilistic...
      v[parser.generate["abs"]] = true
    end
    assert_equal({3 => true, -3 => true}, v)
    assert parser.validate_for_test({"abs" => 3})
    assert parser.validate_for_test({"abs" => -3})
  end


  def test_empty_type_socket
    parser = CDDL::Parser.new <<HERE
a = {b}
b = ( "abs": $t1 )
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "simple_type_augmented RULES:"
    # pp parser.rules
    assert_raise { parser.generate }
  end


  def test_empty_group_socket
    parser = CDDL::Parser.new <<HERE
a = {$$t2}
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "simple_type_augmented RULES:"
    # pp parser.rules
    assert_raise { parser.generate }
  end


  def test_validate_empty_type_socket
    parser = CDDL::Parser.new <<HERE
a = {b}
b = ( "abs": $t1 / 17 )
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "simple_type_augmented RULES:"
    # pp parser.rules
    assert_equal parser.generate, {"abs" => 17}
    assert parser.validate_for_test({"abs" => 17})
  end


  def test_validate_empty_group_socket
    parser = CDDL::Parser.new <<HERE
a = {$$t2 // a: 1}
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "simple_type_augmented RULES:"
    # pp parser.rules
    assert_equal parser.generate, {"a" => 1}
    assert parser.validate_for_test({"a" => 1})
  end


  def test_validate_empty_group_socket_in_star
    parser = CDDL::Parser.new <<HERE
a = {* $$t2}
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "simple_type_augmented RULES:"
    # pp parser.rules
    assert_equal parser.generate, {}
    assert parser.validate_for_test({})
  end

  def test_aaa_validate_more_socket_in_star
    parser = CDDL::Parser.new <<HERE
tcp-header = {seq: uint, ack: uint, * $$tcp-option}

; later, in a different file

$$tcp-option //= (
sack: [+(left: uint, right: uint)]
)

; and, maybe in another file

$$tcp-option //= (
sack-permitted: true
)
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "simple_type_augmented RULES:"
    # pp parser.rules
    10.times do
      g = parser.generate
      pp g
      assert parser.validate_for_test(g)
    end
    assert parser.validate_for_test({"seq" => 1, "ack" => 2})
  end


  def test_simple_type_augmented_uninitialized
    parser = CDDL::Parser.new <<HERE
a = {b}
b = ( "abs": t1 )
t1 /= 3
t1 /= -3
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "simple_type_augmented_uninitialized RULES:"
    # pp parser.rules
    assert_equal(["abs"], parser.generate.keys)
    v = {}
    10.times do
      v[parser.generate["abs"]] = true
    end
    assert_equal({3 => true, -3 => true}, v)
    assert parser.validate_for_test({"abs" => 3})
    assert parser.validate_for_test({"abs" => -3})
  end


  def test_empty_group_indirect
    parser = CDDL::Parser.new <<HERE
a = {b}
b = (c)
c = ()
HERE
# XXX: Pending
#    assert_equal({}, parser.generate)
#    assert parser.validate_for_test({})
  end

  def test_group_occur
    parser = CDDL::Parser.new <<HERE
a = [1*3 b]
b = (
1, 2
)
HERE
    parser2 = CDDL::Parser.new <<HERE
a = [1*3 (1, 2)]
HERE
    # puts "empty_group_sp AST:"
    # puts parser.ast_debug
    # puts "empty_group_sp RULES:"
    pp parser.rules
    assert_equal parser.rules, parser2.rules
    # assert parser.validate_for_test({})
    10.times {
      g = parser2.generate
      # pp ["group-occur", g]
      assert [2, 4, 6].include? g.size
      g.each_slice(2) do |sl|
        assert_equal sl, [1, 2]
      end
      assert parser2.validate_for_test(g)
      refute parser2.validate_for_test(g << 1, false)
    }
  end

  def test_aaa_grpchoice
    parser = CDDL::Parser.new <<HERE
result = [2*2 identifier]
identifier //= ( "ifmap" // "ifmap")
;identifier = ( "ifmap" // "ifmap" )
HERE
    p parser.rules
    # - [:type1, [:array, [:member, 2, 2, nil, [:grpchoice, [[:member, 1, 1, nil, [:text, "ifmap"]]]]]]]
    # - [:type1, [:array, [:member, 2, 2, nil, [:grpchoice, [[:grpchoice, [[:member, 1, 1, nil, [:text, "ifmap"]]], [[:member, 1, 1, nil, [:text, "ifmap"]]]]]]]]]
    # + [:type1, [:array, [:member, 2, 2, nil, [:grpent, [:grpchoice, [[:member, 1, 1, nil, [:text, "ifmap"]]], [[:member, 1, 1, nil, [:text, "ifmap"]]]]]]]]
    g = parser.generate
    assert_equal g, ["ifmap", "ifmap"]
  end

  def test_aaaa_plus_with_choice
    parser = CDDL::Parser.new <<HERE
response = [*locator / divert]
locator = 3
divert = 4
HERE
    assert_equal [:type1, [:array, [:member, 0, CDDL::MANY, nil, [:type1, [:int, 3], [:int, 4]]]]], parser.rules
    parser = CDDL::Parser.new <<HERE
response = [*(locator / divert)]
locator = 3
divert = 4
HERE
    assert_equal [:type1, [:array, [:member, 0, CDDL::MANY, nil, [:type1, [:int, 3], [:int, 4]]]]], parser.rules
    parser = CDDL::Parser.new <<HERE
response = [*locator // divert // objective]
locator = 3
divert = 4
objective = 5
HERE
    assert_equal [:type1, [:array, [:grpchoice, [[:member, 0, CDDL::MANY, nil, [:int, 3]]], [[:member, 1, 1, nil, [:int, 4]]], [[:member, 1, 1, nil, [:int, 5]]]]]], parser.rules
    # 10.times do
    #   p parser.generate
    # end
    parser = CDDL::Parser.new <<HERE
response = [*locator // divert / objective]
locator = 3
divert = 4
objective = 5
HERE
    assert_equal [:type1, [:array, [:grpchoice, [[:member, 0, CDDL::MANY, nil, [:int, 3]]], [[:member, 1, 1, nil, [:type1, [:int, 4], [:int, 5]]]]]]], parser.rules
    # 10.times do
    #   p parser.generate
    # end
  end

  def test_false_map_values
    parser = CDDL::Parser.new <<HERE
a = {a: nil}
HERE
    g = parser.generate
    assert parser.validate_for_test(g)
    assert_equal g, {"a" => nil}
    assert_equal g.cbor_clone, {"a" => nil}
  end

  def test_extractor_ignores_map
    parser = CDDL::Parser.new <<HERE
a = {a: nil,
     beer: mtype, wine: bytes, ? optional: text, cantindex: int}
mtype = 1/2/3 ; can't generate anything meaningful here.
HERE
    d = parser.defines("FOO")
    assert_equal "", d
  end

  def test_extractor_type1
    parser = CDDL::Parser.new <<HERE
BAR = a/b/c
a = 1
b = 2
c = 3
d = 4
HERE
    expected = <<HERE
#define FOO_a 1
#define FOO_b 2
#define FOO_c 3
#define FOO_d 4
#define FOO_BAR_a 1
#define FOO_BAR_b 2
#define FOO_BAR_c 3
HERE
    d = parser.defines("FOO")
    assert_equal expected, d
  end

  def test_extractor_type1_format_string
    parser = CDDL::Parser.new <<HERE
BAR = a/b/c
a = 1
b = 2
c = 3
d = 4
HERE
    expected = <<HERE
C_a = 1
C_b = 2
C_c = 3
C_d = 4
C_BAR_a = 1
C_BAR_b = 2
C_BAR_c = 3
HERE
    d = parser.defines("C_%s = %s")
    assert_equal expected, d
  end

  def test_extractor_enum
    parser = CDDL::Parser.new <<HERE

foo = enum1; why exactly do we need this one?

enum1 = &(
      one: 1
      two: 2
      three: 3
      enum2
)

enum2 = (
      four: 4
      five: 5
)

HERE
    expected = <<HERE
#define FOO_enum1_one 1
#define FOO_enum1_two 2
#define FOO_enum1_three 3
#define FOO_enum1_four 4
#define FOO_enum1_five 5
HERE
    d = parser.defines("FOO")
    assert_equal expected, d
  end

  def test_extractor_array
    parser = CDDL::Parser.new <<HERE
message = [mtype,
           beer: enum1, wine: bytes, ? optional: text, cantindex: int]
enum1 = &( one: 1, two: 2)
mtype = 1/2/3 ; can't generate anything meaningful here.
HERE
    expected = <<HERE
#define FOO_message_mtype_index 0
#define FOO_message_beer_index 1
#define FOO_message_wine_index 2
#define FOO_message_optional_index 3
#define FOO_enum1_one 1
#define FOO_enum1_two 2
HERE
    d = parser.defines("FOO")
    assert_equal expected, d
  end


end
