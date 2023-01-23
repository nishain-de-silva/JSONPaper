# JSONStore (v 1.0)

Swift is a type constrained lanuage right ? The default way of parsing JSON is to parse json string to a known `Codable` JSON structure. But most of the time you may put hand on unknown JSON structures and difficult to define those structures for all scenarios. JSONStore help you to parse JSON in any free form and extract value without constraining into a fixed type. This is pure zero dependency `Swift` package with simplistic `Read Only Until Value Dicovered` design in mind in a single read cycle and theorically should be performant.

## Installation

You can use `Swift Package Manager` to Install `JSONStore` from this repository url. Thats it!

## Usage

> **Warning**
> The library does `not` handle incorrect `JSON` formats and some escaped characters (`\"`, `\t` and `\n`) in `JSON` string. Please make sure to sanatize input string in such cases or otherwise would give you incorrect or unexpected value(s).

To access attribute or element you can you a simple `string` path seperated by dot (**`.`**) notation.
```swift
import JSONStore

let jsonText = String(data: apiDataBytes, encoding: .utf8)

let nameValue:String = JSONEntity(jsonText).string("properyA.properyB.2") ?? "default value"
```
you can use number to access element in an array
and then use methods. You can use the following methods to access value of given `optional` path
## Public Methods

- `string()`
- `array()`
- `bool()`
- `number()`
- `object()`
- `array()`
- `value()`
- `isNull()`
- `isExist()`
- `entries()`
- `type()`


If the key / index does not exist in given path or if the value is another data type from expected formated (except for `string()` see [Exceptions](#exceptional-situations)) then `nill` would be given. You don't need to worry about optional chaining you will recieve `nil` if intermediate path also did not exist.

example:
```swift
JSONEntity(jsonText).number("people.2.details.age") // return age

JSONEntity(jsonText).number("people.2.wrongKey.details.age") // return nil

JSONEntity(jsonText).number("people.2.details.name") // return nil since name is not a number
```

To check if an value is `null` use `isNull()` method don't assume `nil` as `null` it could be value does not exist at all. `isNull` gives `boolean` based on value is actually `null` or or `nil` if value is not found.

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

### parsing string values

for `number` and `boolean` you can parse from `string` by using `ignoreType` parameter by default it is `false`
- for booleans the string values must be `"true"` or `"false"` (case-sensitive) only.

```json
{
    "pathA": {
        "numString": "35"
    }
}
```

```swift
 let value = jsonReference.number("pathA.numString") // return nil

 let value = jsonReference.number("pathA.numString", ignoreType = true) // return 35
```

## Handling unknown types

So how do you get value of unknown types ? You can use `value()` method. It gives the natural value of an attribute as a `tuple` containing (key: `Any?`, type: `JSONType`).

If you want to recieve values in `primitive` types you can use `serializable` parameter (by default `false`). This make `array` and `object` type to be recieved as `string` format. Hence you only recieve types within (`nil`, `Double`, `String` and `Bool`) only.

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
.object | JsonEntity
.array | [JsonEntity]
.null | `nil`

you could additionally use `type()` to get data type of current json `reference`


## Exceptional Situations

- Suppose you access a property like this:
    ```swift
    let value =  JSONEntity(jsonText).string("keyA.keyB.keyC")
    ```
    In JSON data if keyB happens to be an `string` or another primitive type instead of container type of either `object` or `array` then last found intermediete primitive value (in this case string value of keyB) will be return instead of `nil`.

- if you are not sure of sure of data type particular of an attribute or `dumping` pourpose you can always use `.string(attributePath)` as it always give the value as a `string` format unless attribute was not found which would give `nil`.

### Author and Main Contributor
@Nishain De Silva