require 'prettyprint'
require 'cbor-diagnostic'
require 'delegate'

class CBOR::PP < PrettyPrint
  # Outputs +obj+ to +out+ in pretty printed format of
  # +width+ columns in width.
  #
  # If +out+ is omitted, <code>$></code> is assumed.
  # If +width+ is omitted, 79 is assumed.
  #
  # CBOR::PP.pp returns +out+.
  def self.pp(obj, out=$>, width=79)
    q = new(out, width)
    q.pp obj
    q.flush
    #$pp = q
    out << "\n"
  end

  module PPMethods
    # Adds +obj+ to the pretty printing buffer
    # using Object#cbor_pp.
    def pp(obj)
      group {obj.cbor_pp self}
    end

    # XXX: a nested group that is broken should not have things added at the end
    def comma_breakable
      text ','
      fill_breakable
    end

    def seplist(list, sep=nil, iter_method=:each) # :yield: element
      sep ||= lambda { comma_breakable }
      first = true
      list.__send__(iter_method) {|*v|
        if first
          first = false
        else
          sep.call
        end
        yield(*v)
      }
    end

    # A pretty print for a Hash
    def pp_hash(obj, anno)
      s = "#{anno}{"
      group(1, s, '}') {
        seplist(obj, nil, :each_pair) {|k, v|
          group {
            pp k
            text ':'
            group(1) {
              breakable ' '
              pp v
            }
          }
        }
      }
    end
  end

  include PPMethods

  module ObjectMixin # :nodoc:
    def cbor_pp(q)
      if @cbor_annotation
        q.text cbor_annotation_format
      end
      q.text cbor_diagnostic
    end
    def cbor_annotation_add(v)
      unless frozen?
        @cbor_annotation ||= []
        @cbor_annotation << v unless @cbor_annotation.include? v
      end
    end
    def cbor_annotation_replace(v)
      @cbor_annotation = [v]
    end
    def cbor_annotations
      @cbor_annotation
    end
    def cbor_annotation_format
      if @cbor_annotation
        "/" << @cbor_annotation.join(", ") << "/ "
      end
    end
    def cbor_add_annotations_from(ann_list)
      _data, anno = ann_list.find{|data, _anno| equal?(data)}
      f = anno.cbor_annotations
      f.each {|a| cbor_annotation_add(a)} if f
    end
    def cbor_clone
      if frozen?
        CBOR::PP::Cloak.new(self)
      else
        self
      end
    end
    def eql?(other)
      if other.respond_to? :__getobj__
        eql? other.__getobj__
      else
        super
      end
    end
  end

  module EqlMixin
    def eql?(other)
      if other.respond_to? :__getobj__
        eql? other.__getobj__
      else
        super
      end
    end
    # def ==(other)
    #   eql?(other) || super
    # end
  end

  def self.add_annotations(tree, ann_list)
    tree.cbor_add_annotations_from(ann_list)
  end

  class Cloak < ::SimpleDelegator
    def class
      @delegate_sd_obj.class
    end
    include CBOR::PP::ObjectMixin
  end
end

class Class
  def ===(other)
    if other.respond_to? :__getobj__
      other.__getobj__.kind_of? self
    else
      other.kind_of? self
    end
  end
end

class String
  def cbor_clone
    frozen? ? dup : self
  end
end

class Array # :nodoc:
  def cbor_pp(q) # :nodoc:
    s = "#{cbor_annotation_format}["
    q.group(1, s, ']') {
      q.seplist(self) {|v|
        q.pp v
      }
    }
  end
  def cbor_add_annotations_from(ann_list)
    super
    each {|m| m.cbor_add_annotations_from(ann_list)}
  end
  def cbor_clone
    map(&:cbor_clone)
  end
end

class Hash # :nodoc:
  def cbor_pp(q) # :nodoc:
    q.pp_hash self, cbor_annotation_format
  end
  def cbor_add_annotations_from(ann_list)
    super
    each {|k, v|
      # k.cbor_add_annotations_from(ann_list)
      v.cbor_add_annotations_from(ann_list)
    }
  end
  def cbor_clone
    # to_a.cbor_clone.to_h  # this breaks for unknown reasons
    h = {}
    each {|k, v| h[k.cbor_clone] = v.cbor_clone}
    each {|k, v| fail [h, k, k.cbor_clone, h[k], v].inspect unless h[k] == v}
    h
  end
end

class Float                     # Hmm.
  prepend CBOR::PP::EqlMixin
end

class Numeric
  prepend CBOR::PP::EqlMixin
end

class TrueClass
  prepend CBOR::PP::EqlMixin
end

class FalseClass
  prepend CBOR::PP::EqlMixin
end

class NilClass
  prepend CBOR::PP::EqlMixin
end

class Object < BasicObject # :nodoc:
  include CBOR::PP::ObjectMixin
end
