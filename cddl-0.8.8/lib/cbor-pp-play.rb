require_relative "cbor-pp"

a = [1, {foo: "bar", busel: "basel", baz: "bass", ant: "cat", bat: "dog", eel: "fox"},
             2, 3, 4, [3]*55, "foo".b, 0.00006103515625, 0.0000099, 1e-7, nil]
a[1].cbor_annotation_add "fasel"
CBOR::PP.pp a

a = [1, "baz", 3]
a.cbor_annotation_add "foo"
a[1].cbor_annotation_add "bar"
CBOR::PP.pp(a)

p 1.cbor_annotation_format
