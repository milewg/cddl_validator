require 'abnc'
require 'pp'
require 'pathname'
require 'cbor-pure' unless defined?(CBOR::Tagged)
require 'regexp-examples'
require 'colorize'
require 'base64'

module CDDL

  DATA_DIR = Pathname.new(__FILE__).split[0] + '../data'

  PRELUDE = File.read("#{DATA_DIR}/prelude.cddl")
  ABNF_SPEC = File.read("#{DATA_DIR}/cddl.abnf")

  MANY = Float::INFINITY

  MAX_RECURSE = 128              # XXX

  class ParseError < ArgumentError; end

  class Parser

    class BackTrack < Exception; end

    def initialize(source_text)
      @abnf = Peggy::ABNF.new
      _cresult = @abnf.compile! ABNF_SPEC, ignore: :s
      presult = @abnf.parse? :cddl, (source_text + PRELUDE)
      expected_length = source_text.length + PRELUDE.length
      if expected_length != presult
        upto = @abnf.parse_results.keys.max
        puts "UPTO: #{upto}" if $advanced
        pp @abnf.parse_results[upto] if $advanced
        pp @abnf.parse_results[presult] if $advanced
        puts "SO FAR: #{presult}"  if $advanced
        puts @abnf.ast? if $advanced
        presult ||= 0
        part1 = source_text[[presult - 100, 0].max...presult]
        part3 = source_text[upto...[upto + 100, source_text.length].min]
        if upto - presult < 100
          part2 = source_text[presult...upto]
        else
          part2 = source_text[presult, 50] + "......." + source_text[upto-50, 50]
        end
        warn "*** Look for syntax problems around the #{
               "%%%".colorize(background: :light_yellow)} markers:\n#{
               part1}#{"%%%".colorize(color: :green, background: :light_yellow)}#{
               part2}#{"%%%".colorize(color: :red, background: :light_yellow)}#{
               part3}"
        raise ParseError, "*** Parse error at #{presult} upto #{upto} of #{
                          source_text.length} (#{expected_length})."
      end
      puts @abnf.ast? if $debug_ast
      @ast = @abnf.ast?
      # our little argument stack for rule processing
      @insides = []
    end

    def apr                     # for debugging
      @abnf.parse_results
    end

    def ast_debug
      ast.to_s[/.*comment/m]    # stop at first comment -- prelude
    end

    def strip_nodes(n)
      [n[0], *n[1..-1].map {|e|
        e._strip
      }]
    end

    def walk(rule, anno = nil, &block)
      r = []
      case rule
      when Array
        r.concat(Array(yield rule, anno))
        case rule[0]
        when :type1, :array, :map
          a = (rule.cbor_annotations rescue nil) if rule.size == 2
          a = a.first if a
          r.concat(rule[1..-1].map{|x| walk(x, a, &block)})
        when :grpchoice
          r.concat(rule[1..-1].map{|x| x.flat_map {|y| walk(y, &block)}})
        when :member
          r << walk(rule[3], &block)
          r << walk(rule[4], &block)
        when :anno
          r << walk(rule[2], &block)
          r << walk(rule[3], &block)
        else
          # p ["LEAF", rule[0]]
        end
      end
      r.compact
    end

    def cname(s)
      s.to_s.gsub(/-/, "_")
    end

    # Generate some simple #define lines from the value-only rules
    def defines(prefix)
      prefix ||= "CDDL"
      if prefix =~ /%\d*\$?s/
        format = prefix
        format += "\n" unless format[-1] == "\n"
      else
        format = "#define #{prefix}_%s %s\n"
      end
      s = {}                    # keys form crude set of defines
      add = proc { |*a| s[format % a] = true }
      r = rules
      ast.each :rule do |rule|
        if rulename = rule.typename
          t = rule.type.children(:type1)
          if t.size == 1
            if (t2 = t.first.children(:type2)) && t2.size == 1 && (v = t2.first.value)
              add.(cname(rulename), v.to_s)
            end
          end
        end
      end
      # CBOR::PP.pp r
      walk(r) do |subtree, anno|
        if subtree[0] == :type1 && subtree[1..-1].all? {|x| x[0] == :int}
          if enumname = subtree.cbor_annotations rescue nil
            enumname = cname(enumname.first)
            subtree[1..-1].each do |x| 
              if memname = x.cbor_annotations
                memname = "#{enumname}_#{cname(memname.first)}"
                add.(memname, x[1].to_s)
              end
            end
          end
        end
        if subtree[0] == :array
          if (arrayname = subtree.cbor_annotations rescue nil) || anno
            arrayname = cname(arrayname ? arrayname.first : anno)
            subtree[1..-1].each_with_index do |x, i|
              if x[0] == :member
                if Array === x[3] && x[3][0] == :text
                  memname = x[3][1] # preferably use key string
                elsif memname = x[4].cbor_annotations
                  memname = memname.first # use value annotation otherwise
                end
                if memname
                  memname = "#{arrayname}_#{cname(memname)}_index"
                  add.(memname, i.to_s)
                end
              end
              if x[0] == :member && (x[1] != 1 || x[2] != 1)
                break           # can't give numbers if we have optionals etc.
              end
            end
          end
        end
      end
      s.keys.join
    end

    def rules
      @rules = {}
      @generics = {}
      @bindings = [{}]
      ast.each :rule do |rule|
        rule_ast =
          if rulename = rule.groupname
            [:grpent, rule.grpent]
          elsif rulename = rule.typename
            [:type1, *rule.type.children(:type1)]
          else
            fail "Huh?"
          end
        n = rulename.to_s
        asg = rule.assign.to_s
        if g = rule.genericparm
          if asg != "="
            fail "Augment #{asg.inspect} not implemented for generics"
          end
          ids = g.children(:id).map(&:to_s)
          # puts ["ids", ids].inspect
          if b = @generics[n]
            fail "Duplicate generics definition #{n} as #{rule_ast} (was #{b})"
          end
          @generics[n] = [rule_ast, ids]
        else
          case asg
          when "="
            if @rules[n]
              a = strip_nodes(rule_ast).inspect
              b = strip_nodes(@rules[n]).inspect
              if a == b
                warn "*** Warning: Identical redefinition of #{n} as #{a}"
              else
                fail "Duplicate rule definition #{n} as #{b} (was #{a})"
              end
            end
            @rules[n] = rule_ast
          when "/="
            @rules[n] ||= [:type1]
            fail "Can't add #{rule_ast} to #{n}" unless rule_ast[0] == :type1
            # XXX need to check existing rule as well
            @rules[n].concat rule_ast[1..-1]
            # puts "#{@rules[n].inspect} /="
          when "//="
            @rules[n] ||= [:grpchoice]
            fail "Can't add #{rule_ast} to #{n}" unless rule_ast[0] == :grpent
            # XXX need to check existing rule as well
            if @rules[n][0] == :grpent # widen
              @rules[n] = [:grpchoice, @rules[n]]
            end
            @rules[n] << rule_ast
            # puts "#{@rules[n].inspect} //="
          else
            fail "Unknown assign #{asg.inspect}"
          end
        end
      end
      # pp @generics
      @rootrule = @rules.keys.first # DRAFT: generics are ignored here.
      # now process the rules...
      @stage1 = {}
      result = r_process(@rootrule, @rules[@rootrule])
      r_process("used_in_cddl_prelude", @rules["used_in_cddl_prelude"])
      @rules.each do |n, r|
      #   r_process(n, r)     # debug only loop
        warn "*** Unused rule #{n}" unless @stage1[n]
      end
      if result[0] == :grpent
        warn "Group at top -- first rule must be a type!"
      end
      # end
      # @stage1
      result
    end

    def lookup_recurse_grpent(name)
      rule = @stage1[name]
      # pp rule
      fail unless rule.size == 2
      [rule[0], *rule[1]]
    end

    # Memoize a bit here

    REGEXP_FOR_STRING = Hash.new {|h, k|
      h[k] = Regexp.new("\\A#{k}\\z")
    }

    def generate
      @recursion = 0
      generate1(rules)
    end

    def generate1(where, inmap = false)
      case where[0]
      when :type1
        fail BackTrack.new("Can't generate from empty type choice socket yet") unless where.size > 1
        begin
          chosen = where[rand(where.size-1)+1]
          generate1(chosen)
        rescue BackTrack
          tries = where[1..-1].sample(where.size) - [chosen]
          r = begin
                if tries.empty?
                  BackTrack.new("No suitable alternative in type choice")
                else
                  generate1(tries.pop)
                end
              rescue BackTrack
                retry
              end
          fail r if BackTrack === r
          r
        end
      when :grpchoice
        fail BackTrack.new("Can't generate from empty group choice socket yet") unless where.size > 1
        begin
          chosen = where[rand(where.size-1)+1]
          chosen.flat_map {|m| generate1(m, inmap)}
        rescue BackTrack
          tries = where[1..-1].sample(where.size) - [chosen]
          r = begin
                if tries.empty?
                  BackTrack.new("No suitable alternative in group choice")
                else
                  tries.pop.flat_map {|m| generate1(m, inmap)}
                end
              rescue BackTrack
                retry
              end
          fail r if BackTrack === r
          r
        end
      when :map
        Hash[where[1..-1].flat_map {|m| generate1(m, true)}]
      when :recurse_grpent
        name = where[1]
        rule = lookup_recurse_grpent(name)
        if @recursion < MAX_RECURSE
          @recursion += 1
#p ["recurse_grpent", *rule]
#r = generate1(rule)
          r = rule[1..-1].flat_map {|m| generate1(m, inmap)}
          @recursion -= 1
          r
        else
          fail "Deep recursion into #{name}: #{@stage1[name]}, not yet implemented"
        end
      when :array, :grpent
        r = where[1..-1].flat_map {|m| generate1(m).map{|e| e[1]}}
            .flat_map {|e| Array === e && e[0] == :grpent ? e[1..-1] : [e]}
                           # nested grpents need to be "unpacked"
        if where[0] == :grpent
          [:grpent, *r]
        else
          r
        end
      when :member
        st = where[1]
        fudge = 4 * (1 - (@recursion / MAX_RECURSE.to_f))**3 # get less generate-happy with more recursion
        en = [where[2], [st, fudge].max].min # truncate to fudge unless must be more
        st += rand(en + 1 - st) if en != st
        kr = where[3]
        vr = where[4]
        if inmap
          unless kr
            case vr[0]
            when :grpent
              fail "grpent in map #{vr.inspect}" unless vr.size == 2
              g = Array.new(st) { generate1(vr[1], true) }.flatten(1)
              # warn "GGG #{g.inspect}"
              return g
            when :grpchoice
              g = Array.new(st) { generate1(vr, true) }.flatten(1)
              # warn "GGG #{g.inspect}"
              return g
            else
              fail "member key not given in map for #{where}"  # || vr == [:grpchoice]
            end
          end
        end
        begin
          Array.new(st) { [ (generate1(kr) if kr), # XXX: need error in map context
                            generate1(vr)
                          ]}
        rescue BackTrack
          fail BackTrack.new("Need #{where[1]}..#{where[2]} of these: #{[kr, vr].inspect}") unless where[1] == 0
          []
        end
      when :text, :int, :float, :bytes
        where[1]
      when :range
        rand(where[1])
      when :prim
        case where[1]
        when nil
          gen_word              # XXX: maybe always returning a string is confusing
        when 0
          rand(4711)
        when 1
          ~rand(815)
        when 2
          gen_word.force_encoding(Encoding::BINARY)
        when 3
          gen_word
        when 6
          CBOR::Tagged.new(where[2], generate1(where[3]))
        when 7
          case where[2]
          when nil
            Math::PI
          when 20
            false
          when 21
            true
          when 22
            nil
          when 23
            :undefined
          when 25, 26, 27
            rand()
          end
        else
          fail "Can't generate prim #{where[1]}"
        end
      when :anno
        target = where[2]
        control = where[3]
        case where[1]
        when :size
          should_be_int = generate1(control)
          unless (Array === target && target[0] == :prim && [0, 2, 3].include?(target[1])) && Integer === should_be_int && should_be_int >= 0
            fail "Don't know yet how to generate #{where}"
          end
          s = Random.new.bytes(should_be_int)
          case target[1]
          when 0
            # silently restrict to what we can put into a uint
            s[0...8].bytes.inject(0) {|a, b| a << 8 | b }
          when 2
            s
          when 3
            Base64.urlsafe_encode64(s)[0...should_be_int]
            # XXX generate word a la w = gen_word
          end
        when :bits
          set_of_bits = Array.new(10) { generate1(control) } # XXX: ten?
          # p set_of_bits
          unless (target == [:prim, 0] || target == [:prim, 2]) &&
                 set_of_bits.all? {|x| Integer === x && x >= 0 }
            fail "Don't know yet how to generate #{where}"
          end
          if target == [:prim, 2]
            set_of_bits.inject(String.new) do |s, i|
              n = i >> 3
              bit = 1 << (i & 7)
              if v = s.getbyte(n)
                s.setbyte(n, v | bit); s
              else
                s << "\0" * (n - s.size) << bit.chr(Encoding::BINARY)
              end
            end
          else                  # target == [:prim, 0]
            set_of_bits.inject(0) do |a, v|
              a |= (1 << v)
            end
          end
        when :default
          # Hmm.
          unless $default_warned
            warn "*** Ignoring .default for now."
            $default_warned = true
          end
          generate1(target, inmap)
        when :eq
          content = generate1(control)
          if validate1(content, where)
            return content
          end
          fail "Not smart enough to generate #{where}"
        when :lt, :le, :gt, :ge, :ne
          if Array === target && target[0] == :prim
            content = generate1(control)
            try = if Numeric === content
                    content = Integer(content)
                    case target[1]
                    when 0
                      case where[1]
                      when :lt
                        rand(0...content)
                      when :le
                        rand(0..content)
                      end
                    end
                  end
            if validate1(try, where)
              return try
            else
              warn "HUH gen #{where.inspect} #{try.inspect}" unless try.nil?
            end
          end
          32.times do
            content = generate1(target)
            if validate1(content, where)
              return content
            end
          end
          fail "Not smart enough to generate #{where}"
        when :regexp
          regexp = generate1(control)
          unless target == [:prim, 3] && String === regexp
            fail "Don't know yet how to generate #{where}"
          end
          REGEXP_FOR_STRING[regexp].random_example(max_repeater_variance: 5)
        when :cbor, :cborseq
          unless target == [:prim, 2]
            fail "Don't know yet how to generate #{where}"
          end
          content = CBOR::encode(generate1(control))
          if where[1] == :cborseq
            # remove the first head
            n = case content.getbyte(0) - (4 << 5)
                when 0..23; 1
                when 24; 2
                when 25; 3
                when 26; 5
                when 27; 9      # unlikely :-)
                else fail "Generated .cborseq sequence for #{where} not an array"
                end
            content[0...n] = ''
          end
          content
        when :within, :and
          32.times do
            content = generate1(target)
            if validate1(content, control)
              return content
            elsif where[1] == :within
              warn "*** #{content.inspect} meets #{target.inspect} but not #{control.inspect}"
            end
          end
          fail "Not smart enough to generate #{where}"
        else
          fail "Don't know yet how to generate from #{where}"
        end
      when :recurse
        name = where[1]
        rule = @stage1[name]
        if @recursion < MAX_RECURSE
          @recursion += 1
#p ["recurse", *rule]
          r = generate1(rule)
          @recursion -= 1
          r
        else
          fail "Deep recursion into #{name}: #{@stage1[name]}, not yet implemented"
        end
      else
        fail "Don't know how to generate from #{where[0]} in #{where.inspect}"
      end
    end

    VALUE_TYPE = {text: String, int: Integer, float: Float}
    SIMPLE_VALUE = {
      [:prim, 7, 20] => [true, false, :bool],
      [:prim, 7, 21] => [true, true, :bool],
      [:prim, 7, 22] => [true, nil, :nil],
      [:prim, 7, 23] => [true, :undefined, :undefined],
    }

    def extract_value(t)        # []
      if vt = VALUE_TYPE[t[0]]
        [true, t[1], vt]
      elsif v = SIMPLE_VALUE[t]
        v
      else
        [false]
      end
    end

    def validate_diag
      [@last_data, @last_rule, @last_message]
    end
    def validate_log
      if @last_message.to_s.length > 500
        @last_message.to_s[0, 500]
      else
        @last_message
      end
    end

    def validate(d, warn=true)
      @recursion = 0
      result = validate1a(d, rules)
      unless result
        if warn
          warn "CDDL validation failure" #{d.inspect}"
          if $flagOfNotFind == 0
            warn $arrNotFind.to_s
          end
          PP::pp(validate_log, STDERR)
          # PP::pp(validate_diag, STDERR)
        end
      end
      result
    end

    def validate_result(check)
      check || (
        @last_message = yield
        false
      )
    end

    def validate_forward(d, start, where)
      # warn ["valforw", d, start, where].inspect
      i = 0
      ann = []
      where[1..-1].each { |r|
        t, s, e, _k, v = r # XXX
        if t == :recurse_grpent
          rule = lookup_recurse_grpent(s)
          n, ann2 = validate_linear(d, start+i, rule)
          return [false, ann] unless n
          i += n
          ann.concat(ann2)
        elsif t == :grpchoice
          return [false, ann] unless r[1..-1].any? {|cand|
            n, ann2 = validate_forward(d, start+i, [:foo, *cand])
            if n
              i += n
              ann.concat(ann2)
            end}
        else
          fail r.inspect unless t == :member
          occ = 0
          while ((occ < e) && i != d.size && ((n, ann2 = validate_linear(d, start+i, v)); n))
            i += n
            occ += 1
            ann.concat(ann2)
          end
          if occ < s
            # @last_message = "occur not reached in array"  #{d} for #{where}"
            return [false, ann]
          end
        end
      }
      # warn ["valforw>", i].inspect
      [i, ann]
    end

    # returns number of matches or false for breakage
    def validate_linear(d, start, where)
      # warn ["vallin", d, start, where].inspect
      fail unless Array === d
      case where[0]
      when :grpent
        # must be inside an array with nested occurrences
        validate_forward(d, start, where)
      else
        (ann = validate1a(d[start], where)) ? [1, ann] : [false, ann]
      end
    end

    def map_check(d, d_check, members)
      anno = []
      anno if members.all? { |r|
        puts "ALL SUBRULE: #{r.inspect}"         if ENV["CDDL_TRACE"]
        t, s, e, k, v = r
        case t
        when :recurse_grpent
          rule = lookup_recurse_grpent(s)
          if ann2 = map_check(d, d_check, rule[1..-1])
            anno.concat(ann2)
          end
        when :grpchoice
          r[1..-1].any? {|cand|
            puts "CHOICE SUBRULE: #{cand.inspect}"         if ENV["CDDL_TRACE"]
            cand_d_check = d_check.dup
            if ann2 = map_check(d, cand_d_check, cand)
              puts "CHOICE SUBRULE SUCCESS: #{cand.inspect}"         if ENV["CDDL_TRACE"]
              d_check.replace(cand_d_check)
              anno.concat(ann2)
            end
          }
        when :member
          unless k
            case v[0]
            when :grpent
              entries = v[1..-1]
            when :grpchoice
              entries = [v]
            else
              fail "member name not known for group entry #{r} in map"
            end
            d_check1 = d_check.dup
            occ = 0
            ann2 = []
            while occ < e && (ann3 = map_check(d, d_check1, entries)) && ann3 != []
              occ += 1
              ann2.concat(ann3)
            end
            if occ >= s
              d_check.replace(d_check1)
              anno.concat(ann2)
              puts "OCC SATISFIED: #{occ.inspect} >= #{s.inspect}" if ENV["CDDL_TRACE"]
              anno
            else
              # leave some diagnostic breadcrumbs?
              puts "OCC UNSATISFIED: #{occ.inspect} < #{s.inspect}" if ENV["CDDL_TRACE"]
              false
            end
          else
          # this is mostly quadratic; let's do the linear thing if possible
          simple, simpleval = extract_value(k)
          if simple
                          puts "SIMPLE: #{d_check.inspect} #{simpleval}"         if ENV["CDDL_TRACE"]
            # add occurrence check; check that val is present in the first place
            actual = d.fetch(simpleval, :not_found)
            if actual == :not_found
              $arrNotFind = d_check.to_s[0,600]
              s == 0          # minimum occurrence must be 0 then
            else
              if (ann2 = validate1a(actual, v)) &&
                 d_check.delete(simpleval) {:not_found} != :not_found
                anno.concat(ann2)
              end
            end
          else
                          puts "COMPLEX: #{k.inspect} #{simple.inspect} #{simpleval.inspect}"         if ENV["CDDL_TRACE"]
            keys = d_check.keys
            ta, keys = keys.partition{ |key| validate1(key, k)}
            # XXX check ta.size against s/e
            ta.all? { |val|
              if (ann2 = validate1a(d[val], v)) && 
                 d_check.delete(val) {:not_found} != :not_found
                anno.concat(ann2)
              end
            }
          end
          end
        else
          fail "Cannot validate #{t} in maps yet #{r}" # MMM
        end
      }
    end

    def validate1a(d, where)
      if ann = validate1(d, where)
        here = [d, where]
        if Array === ann
          [here, *ann]
        else
          [here]
        end
      end
    end

    OPERATORS = {lt: :<, le: :<=, gt: :>, ge: :>=, eq: :==, ne: :!=}
    $flagOfNotFind = 0
    def validate1(d, where)
      if ENV["CDDL_TRACE"]
        puts "DATA: #{d.inspect}"
        puts "RULE: #{where.inspect}"
      end
      # warn ["val1", d, where].inspect
      @last_data = d
      @last_rule = where
      ann = nil
      case where[0]
      when :type1
        if where[1..-1].any? {|r| ann = validate1a(d, r)}
          ann
        end
      when :map
        if Hash === d
          d_check = d.dup
          if (ann = map_check(d, d_check, where[1..-1]))
            if d_check.to_s != "{}"
              $flagOfNotFind = 1
              warn d_check.to_s[0,600]
            else
              ann
            end
          else
            if ENV["CDDL_TRACE"]
              puts "MAP RESIDUAL: #{d_check.inspect} for #{where[1..-1]} and #{d.inspect}"
            end
          end
        end
      when :array
        # warn ["valarr", d, where].inspect
        if Array === d
          # validate1 against the record
          idx, ann = validate_forward(d, 0, where)
          ann if validate_result(idx == d.size) { "#{validate_diag.inspect} -- cannot complete (#{idx}, #{d.size})"} # array #{d}  for #{where}" }
        end
      when :text, :int, :float, :bytes
        _, v = extract_value(where)
        [] if d == v
      when :range
        [] if where[2] === d && where[1].include?(d)
      when :anno
        target = where[2]
        if ann = validate1a(d, target)
          control = where[3]
          case where[1]
          when :size
            case d
            when Integer
              ok, v, vt = extract_value(control)
              if ok && vt == Integer
                ann if (d >> (8*v)) == 0
              end
            when String
              ann if validate1(d.bytesize, control)
            end
          when :bits
            if String === d
              d.each_byte.with_index.all? { |b, i|
                bit = i << 3
                ann if 8.times.all? { |nb|
                  b[nb] == 0 || validate1(bit+nb, control)
                }
              }
            elsif Integer === d
              if d >= 0
                ok = true
                i = 0
                while ok && d > 0
                  if d.odd?
                    ok &&= validate1(i, control)
                  end
                  d >>= 1; i += 1
                end
                ann if ok
              end
            end
          when :default
            # Hmm.
            unless $default_warned
              warn "*** Ignoring .default for now."
              $default_warned = true
            end
            ann
          when :lt, :le, :gt, :ge, :eq, :ne
            op = OPERATORS[where[1]]
            ok, v, _vt = extract_value(control)
            if ok
              ann if d.send(op, v) rescue nil # XXX Focus ArgumentError
            end
          when :regexp
            ann if (
            if String === d
              ok, v, vt = extract_value(control)
              if ok && vt == String
                re = REGEXP_FOR_STRING[v]
                # pp re
                d.match(re)
              end
            end
            )
          when :cbor
            ann if validate1((CBOR::decode(d) rescue :BAD_CBOR), control)
          when :cborseq
            ann if validate1((CBOR::decode("\x9f".b << d << "\xff".b) rescue :BAD_CBOR), control)
          when :within
            if validate1(d, control)
              ann
            else
              warn "*** #{d.inspect} meets #{target} but not #{control}"
              nil
            end
          when :and
            ann if validate1(d, control)
          else
            fail "Don't know yet how to validate against #{where}"
          end
        end
      when :prim
        # warn "validate prim WI #{where.inspect} #{d.inspect}"
        case where[1]
        when nil
          true
        when 0
          Integer === d && d >= 0 && d <= 0xffffffffffffffff
        when 1
          Integer === d && d < 0 && d >= -0x10000000000000000
        when 2
          String === d && d.encoding == Encoding::BINARY
        when 3
          String === d && d.encoding != Encoding::BINARY # cheat
        when 6
          # CBOR::Tagged === d && d.tag == where[2] && validate1a(d.data, where[3])
          if CBOR::Tagged === d                  # Validate in case of CBOR
            d.tag == where[2] && validate1a(d.data, where[3])
          else                                   # Validate in case of JSON
            idxOpenParentheses = d.index('(')
            idxCloseParentheses = d.index(')')
            if idxOpenParentheses != nil && idxCloseParentheses != nil
              tagString = d[0,idxOpenParentheses]
              if /^\d+$/.match(tagString) != nil
                tag = tagString.to_i
                data = d[idxOpenParentheses + 1, idxCloseParentheses - (d[0,idxOpenParentheses].size + 1)]
                tag == where[2] && validate1a(data, where[3])
              else
                warn "Error! Tag can only be number..."
              end
            else
              warn "Error! This is not one tag type!!!"
            end
          end
        when 7
          t, v = extract_value(where)
          if t
            v.eql? d
          else
            case where[2]
            when nil
              # XXX
              fail
            when 25, 26, 27
              Float === d
            else
              fail
            end
          end
        else
          fail "Can't validate prim #{where[1]} yet"
        end
      when :recurse
        name = where[1]
        rule = @stage1[name]
        if @recursion < MAX_RECURSE
          @recursion += 1
          r = validate1a(d, rule)
          @recursion -= 1
          r
        else
          fail "Deep recursion into #{name}: #{rule}, not yet implemented"
        end
      else
        @last_message = "Don't know how to validate #{where}"
        false
        # fail where
      end
    end


    attr_reader :ast

    private

    def gen_word
      @words ||= (File.read("/usr/share/dict/words").lines.shuffle rescue %w{tic tac toe})
      @wordptr ||= 0
      @wordptr = 0 if @wordptr == @words.size
      w = @words[@wordptr].chomp
      @wordptr += 1
      w
    end

    def rule_lookup(name, canbegroup)
      if b = @bindings.last[name]
        b
      else
        r = @rules[name]
        unless r
          if name[0] == "$"
            r = @rules[name] = if name[1] == "$"
                                 [:grpchoice]
                               else
                                 [:type1]
                               end
          end
        end
        if r
          t = r_process(name, r)
          unless t[0] == :type1
            fail "#{name} not a type #{t}" unless canbegroup && (t[0] == :grpent || t[0] == :grpchoice)
          end
          t
        end
      end
    end

    RECURSE_TYPE = {grpent: :recurse_grpent, grpchoice: :recurse_grpent,
                    type1: :recurse} # MMM
    RECURSE_TYPE.default_proc = proc do |a|
      fail a.inspect
    end

    def r_process(n, r, bindings = {})
      t = r[0]
      # puts "Processing rule #{n} = #{t}"
      @stage1[n] ||= begin
                       @stage1[n] = [t, [RECURSE_TYPE[t], n]]
                       @bindings.push(bindings)
                       r = [t, *r[1..-1].map {|e|
                              case t
                              when :grpchoice
                                fail e[0].inspect unless e[0] == :grpent
                                fail e unless e.size == 2
                                res = grpent(e[1])
                                # warn "RES #{res.inspect}"
                                res
                              when :grpent
                                grpent(e)
                              when :type1
                                type1(e, r.size == 2) # a single type1 could be a group
                              else
                                fail t
                              end}]
                       @bindings.pop
                       r.cbor_annotation_add(n) rescue nil # AAA
                       r
                     end
    end

    def value(n)
      # cheat:
      # warn n
      s = n.to_s
      if s[-1] == "'"
        parts = s.split("'", 3)
        if parts[2] != "" || parts[1] =~ /\\/
          warn "*** Can't handle backslashes in #{s.inspect} yet"
        end
        [:bytes,
         case parts[0]
         when ""
           parts[1].b
         when "h"
           parts[1].gsub(/\s/, "").chars.each_slice(2).map{ |x| Integer(x.join, 16).chr("BINARY") }.join
         when "b64"
            Base64.urlsafe_decode64(parts[1])
         else
           warn "*** Can't handle byte string type #{parts[0].inspect} yet"
         end
        ]
      else
        val = eval(n.to_s)
        # warn val
        case val
         when Integer; [:int, val]
         when Numeric; [:float, val]
         when String; [:text, val.force_encoding(Encoding::UTF_8)]
         else fail "huh? value #{val.inspect}"
        end
      end
    end

    def workaround1(n)
      n.children.each do |ch|
        if ch.to_s == ")"
          # warn "W1 #{ch.inspect} -> #{ch.group.inspect}"
          return ch.group
        end
      end
      nil
    end

    def grpent(n)               # returns array of entries
      occ = occur(n.occur)
      if g = n.group || workaround1(n)
        gr = group(g)
        if occ != [1, 1]
          gr = [[:member, *occ, nil, [:grpent, *gr]]]
        end
        return gr
      end
      nt = n.type || (n.s && n.s.type) || (n.bareword && n.bareword.s.type) # workarounds
      unless nt
        warn "NO NT"
        warn @abnf.ast?
        fail ["ntype", n, n.children].inspect
      end
      if mk = n.memberkey       # work around unclear bug in ast generation below
        if (t1 = mk.type1 || t1 = mk.value ||
                          ((t1 = mk.s) && (t1 = t1.type) && (t1 = t1.type1))) # workaround
          [[:member, *occ, type1(t1), type(nt)]]
        else
          bw = mk.bareword
          unless bw
            warn @abnf.ast?
            fail [n, n.children, mk, mk.children].inspect
          end
          name = bw.to_s
          [[:member, *occ, [:text, name.force_encoding(Encoding::UTF_8)], type(nt)]]
        end
      else
        t = if nbw = nt.bareword
              t1 = nbw.type1 # || n.bareword.s.type.type1 # workaround
              rest = type_collect(nt, true)
              s = [:type1, type1(t1, true), *rest]
              # warn "T2: #{s.size} #{s}" -- maybe this should have a parenthesis warning?
              s.size == 2 ? s[1] : s # decapsulate single-element choice
            else
              type(nt, true)              # type can actually be a group here!
            end
        pp ["t is", t]               if ENV["CDDL_TRACE"]
        if t[0] == :grpent && (occ == [1, 1])
          # go through the members here and multiply the occs
          t1 = t[1..-1].flatten(1)
          if t1[0] == :recurse_grpent
            [t1]
          elsif Array === t1[0] && t1[0][0] == :grpchoice
            fail t1.inspect unless t1.size == 1
            t1
          else
            t1.flat_map {|t2|
              if t2[0] == :member
                [t2]
              else
                fail t1.inspect unless t2[0] == :grpent # XXX Where is the nested multiplication here?
                t2[1..-1]
              end
            }.map {|mem|
              mem[1] *= occ[0]
              mem[2] *= occ[1]    # Does all the infinity magic
              # p mem
              mem
            }
          end
        else
          if t[0] == :grpchoice && occ == [1, 1]
            [t]
          else
            if t[0] == :grpent
              t = [t[0], *t[1..-1].flatten(1)]
            end
            if occ[0] == 0 && t == [:grpchoice]
              []                # we won't be able to generate any of those
            else
              if t[0] == :grpchoice # FIXME: need to package grpchoice into grpent in a member
                t = [:grpent, t]
              end
              [[:member, *occ, nil, t]]
            end
          end
        end
      end
    end

    def g_process(name, g, genericargs)
      r, ids = g
      args = genericargs.children(:type1).map {|x| type1(x, true)}
      fail "number of args #{name} #{ids.size} #{args.size}" if ids.size != args.size
      bindings = Hash[ids.zip(args)]
      r_process("#{name}<#{genericargs._strip}>", r, bindings)
    end

    def type_recall(name, canbegroup, genericargs)
      # p genericargs, "GENERIC"
      if genericargs && (generic = @generics[name])
        t = g_process(name, generic, genericargs)
        t
      elsif !genericargs && (t = rule_lookup(name, canbegroup))
        t
      else
        fail "Unknown type #{name} #{genericargs.inspect} #{@bindings}"  #{@abnf.ast?}"
      end
    end

    def group_recall(name, genericargs)
      if genericargs && (generic = @generics[name])
        g = g_process(name, generic, genericargs)
        fail "#{name} not a group" unless g[0] == :grpent
        g[1..-1]
      elsif !genericargs && (g = rule_lookup(name, true))
        fail "#{name} not a group" unless g[0] == :grpent
        g[1..-1]                # AAA
      else
        fail "Unknown group #{name}"
      end
    end

    def type2(n, canbegroup = false)
      if v = n.type
        type(n.type)
      elsif v = n.value
        value(n)
      elsif v = n.typename
        ga = n.genericarg || (n.s && n.s.genericarg) # workaround
        t = type_recall(v.to_s, canbegroup, ga)
        if t[0] == :type1
          if t.size == 2
            t = t[1]
          else
            t = [:type1, *t[1..-1].flat_map {|t1|
                   if t1[0] == :type1
                     t1[1..-1]
                   else
                     [t1]
                   end
                 }]

          end
        end                     # XXX should flatten the thing, too
        t = t.dup
        t.cbor_annotation_replace(v.to_s) rescue nil # AAA
        t
      else
        fail [n, n.children].inspect
      end
    end

    def memberkey_check(s)
      s.each do |member|
        case member[0]
        when :grpchoice
          member[1..-1].each do |m|
            memberkey_check(m)
          end
        when :recurse_grpent # XXX we don't have the entry yet
        when :member
          # fail "map entry without member key given: #{member}" unless member[3] || member[4][0] == :grpent || member[4][0] == :grpchoice
          msg_value = s.to_s[0,s.to_s.index(member.to_s)]
          length_msg_value = msg_value.length + member.to_s.length*2 + 2
          fail "*** Map entry without member key given, look for syntax problems around the #{"%%%".colorize(background: :light_yellow)} markers:\n #{msg_value} #{"%%%".colorize(background: :light_yellow)} #{member.to_s.colorize(color: :light_red)} #{"%%%".colorize(background: :light_yellow)} #{s.to_s[length_msg_value, length_msg_value + 100]}" unless member[3] || member[4][0] == :grpent || member[4][0] == :grpchoice
        else
          fail ["type1 member", member].inspect unless member[0] == :member
        end
      end
    end

    BRACE = {"{" => :map, "[" => :array}
    RANGE_EXCLUDE_END = {".." => false, "..." => true}
    SUPPORTED_ANNOTATIONS = [:bits, :size, :regexp, :cbor, :cborseq, :within, :and,
                             :default, :lt, :le, :gt, :ge, :eq, :ne]

    def type1(n, canbegroup = false)
#      puts "NVALUE #{n.value.inspect}"
      if v = n.type2
        ch = n.children(:type2)
        if ro = n.rangeop
          cats = []
          [:range, Range.new(*ch.map {|l|
             ok, val, cat = extract_value(type2(l))
             fail "Can't have range with #{l}" unless ok
             # XXX really should be checking type coherence of range
             cats << cat
             val
           }, RANGE_EXCLUDE_END[ro.to_s]),
           cats[0] == cats[1] ? cats[0] : fail("Incompatible range #{cats}")]
        elsif anno = n.annotator
          annotyp = anno.id.to_s.intern
          unless SUPPORTED_ANNOTATIONS.include?(annotyp)
            fail "Unsupported annotation .#{annotyp}"
          end
          [:anno, annotyp, *ch.map {|t| type2(t)}]
        else
          type2(v, canbegroup)
        end
      else
        case str = n.to_s
        when "#"
          [:prim]
        when /\A#(\d+)/
          maj = $1.to_i
          s = [:prim, maj, *n.children(:uint).map(&:to_s).map(&:to_i)]
          if tagged_type = n.type
              s << type(tagged_type)
          end
          s
        when /\A[\[{]/
          type = BRACE[str[0]]
          @insides << type
          s = n.children(:group).flat_map {|g| group(g)}
          @insides.pop
          if type == :map
            memberkey_check(s)
            # XXX could do the occurrence multiplier here
          end
          # warn s.inspect
          [type, *s]
        when /\A&/
          if gn = n.groupname
            s = group_recall(gn.to_s, n.genericarg).flatten(1)
          else
            @insides << :enum
            s = n.children(:group).flat_map {|g| group(g)}
            @insides.pop
          end
          [:type1, *s.map {|mem|
             t, _s, _e, _k, v = mem
             fail "enum #{t.inspect}" unless t == :member
             v.cbor_annotation_add(generate1(_k)) rescue nil # AAA (XXX: what if more than one?)
             v
           }
          ]
        else
          "unimplemented #{n}"
        end
      end
    end

    def type_collect(n, canbegroup)
      n.children(:type1).map {|ch| type1(ch, canbegroup)}
    end

    def type(n, canbegroup = false)
      # pp ["nch", n.children]
      s = type_collect(n, canbegroup)
      if s.size == 1
        s.first
      else
        [:type1, *s]
      end
    end

    def group(n)                # returns array
      choices = n.children(:grpchoice)
      if choices == []          # "cannot happen", workaround
        choices = n.s.children(:grpchoice)
        # warn "W2: #{choices.inspect}"
      end
      choices = choices.map {|choice|
        choice.children(:grpent).flat_map {|ch| grpent(ch)}
      }
      case choices.size
      when 1
        choices.first
      else
        [[:grpchoice, *choices]]
      end
    end

    def occur(n)
      case n.to_s
      when ""
        [1, 1]
      when "+"
        [1, MANY]
      when "?"
        [0, 1]
      when /\A(\d*)\*(\d*)\z/
        if (s = $1) == ""
          s = 0
        else
          s = s.to_i
        end
        if (e = $2) == ""
          e = MANY
        else
          e = e.to_i
        end
        [s, e]
      else
        fail "huh #{n.to_s}"
      end
    end

  end
end
