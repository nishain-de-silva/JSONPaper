# JSONStore (v2) :rocket:

Swift is a type constrained lanuage right ? The default way of parsing JSON is to parse json string to a known `Codable` JSON structure. But most of the time you may put hand on unknown JSON structures and difficult to define those structures for all scenarios. JSONStore help you to parse JSON in any free form and extract value without constraining into a fixed type. This is pure zero dependency `Swift` package with `Read Only Until Value Dicovered` mechanism in a single read cycle and performance efficient.

## Installation

You can use `Swift Package Manager` to Install `JSONStore` from this repository url. Thats it!

## Usage

> **Warning**
> The library does `not` handle incorrect `JSON` format. Please make sure to sanatize input string in such cases or otherwise would give you incorrect or unexpected value(s).

To access attribute or element you can you a simple `string` path seperated by dot (**`.`**) notation.
```swift
import JSONStore

let jsonText = String(data: apiDataBytes, encoding: .utf8)

let nameValue:String = JSONEntity(jsonText).string("properyA.properyB.2") ?? "default value"
```
you can use number to access element in an array
and then use methods. You can use the following methods to access value of given `optional` path

> when accessing array you can use numbers for indexed items. eg: `user.details.contact.2.phoneNumber`
but don't use any brackets

### Query methods
In all query methods if the key / indexed item does not exist in given path or if the value is another data type from expected formated then `nill` would be given. You don't need to worry about optional chaining you will recieve `nil` if intermediate path also did not exist.

example:
```swift
let jsonStore = JSONEntity(jsonText)

jsonStore.number("people.2.details.age") // return age

jsonStore.number("people.2.wrongKey.details.age") // return nil

jsonStore.number("people.2.details.name") // return nil since name is not a number
```

To check if an value is `null` use `isNull()` method don't assume `nil` as `null` it could be value does not exist at all. To be precise use `isNull` which gives `boolean` based on value is actually `null` or `nil` if value entry is not found.

## Initiializing

There are two ways to intitialize JSONStore
```swift
let entity = entity(jsonAsString) 
// or...
let networkData = Data(...)
let entity = JSONEntity()
networkData.withUnsafeBytes(entity.fetchBytes())
```

> The second method may seems strange but JSONStore is a zero dependency library  therefore don't use `Foundation` and cannot resolve `Data` instance types therefore you have to send data from a pointer.
> **Warning**
> **Both input string and data must be represented in `UTC-8` format**

### Iterating values in array

If you need to acesss value is an array you can use:
```swift
guard let hobbies:[JSONEntity] = JSONEntity(jsonText).array("people.2.hobbies") else { return "No hobbies :(" }

hobbies[0].string() // hobby 1
```
### Iterating values in object
You can also iterate values and keys in JSON objects as `tuple` of `key-value` pair. Suppose we have JSON like this

```json
{
    "person": {
        "name": "Sam",
        "age": 25,
        "additionalData": null
    }
}
```


```swift
guard let entries = JSONEntity(jsonText).entries("person") else { return "NotAnObject" }

let attributeKey = entries[0].key // name
let values = entries[0].value.string() // Sam
```

You can also keep record of intermediate `reference instance` for later use and do chaining.

```swift

let pointer = JSONEntity(jsonText).object("pathA.pathB") // return JSONEntity

let keyValue: String? = pointer.string("pathC.key1")

```
> Note that this would not change reference of `pointer` as `.object()` deliver new `JSONEntity` object.

## Parsing data types

for `number`, `boolean`, `object` and `array` you can parsed from `string` by using `ignoreType` parameter (default `false`)
- for booleans the string values must be `"true"` or `"false"` (case-sensitive) only.
- When parsing `object` and `array` the json string should use `escaped` double quotation (`not` single quotations) for string terminators. Of course you have to make sure the string is `valid` JSON as well.

```json
{
    "pathA": {
        "numString": "35"
    },
    "sampleData": "{\"inner\": \"awesome\"}"
}
```

```swift
 let value = jsonReference.number("pathA.numString") // return nil

 let value = jsonReference.number("pathA.numString", ignoreType = true) // return 35

 let value = jsonReference.object("sampleData", ignoreType = true).string("inner") // return awesome
```

## Handling unknown types

So how do you get value of unknown types ? You can use `value()` method. It gives the natural value of an attribute as a `tuple` containing (value: `Any`, type: `JSONType`).

```swift
let (value, type) = jsonRef.value("somePath")

if type == .string {
    // you can safely downcast to string
} else if type == .object {
    // if object..
} // and so on...

```

type  | output
--- | ---
.string | string
.number | double
.boolean | `true` or `false`
.object | JSONEntity
.array | [JSONEntity]
.null | `JSONStore.Constants.NULL`

you could additionally use `type()` to get data type of current json `reference`

## Serializing Data

Sometimes you may need to write the results on `serializable` destination such as in-device cache where you have to omit usage of class instances and unwarp its actual value. You can use `export()` for this, `array` and `object` will be converted to `array` and `dictionary` recursively and other primitive types will be converted in their `natural` values.

_Remember `null` is represented by `JSONStore.Constants.NULL`. This is to avoid optional wrapping._

## Capturing references

`capture()` is used to capture the reference of the given path or clone current instance. You can basically query values in 2 ways:

```swift
let value = reference.string(attributePath)!
// or
let value = reference.capture(attributePath)?.string()
// both gives same result
```

## Exceptional Situations

- Suppose you access a property like this:
    ```swift
    let value =  JSONEntity(jsonText).string("keyA.keyB.keyC")
    ```
    In JSON data if keyB happens to be an `string` or another primitive type instead of container type of either `object` or `array` then last found intermediete primitive value (in this case string value of keyB) will be return instead of `nil`.

- To dump data at a particular node for `debugging` pourpose you can always use `.dump(attributePath)` as it always give the value in `string` format unless attribute was not found which would give `nil`.

## Author and Main Contributor
@Nishain De Silva

`Thoughts` -   _**"** I recently found out it is difficult parse `JSON` on type constrained lanauage unlike in `JavaScript` so I ended up creating my own library for this pourpose! So I thought maybe others face the same problem and why not make other also have a `taste` of what I created **"**_ :sunglasses:
