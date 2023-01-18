# JSONStore (v 1.0)

Swift is a type constrained lanuage right ? The default way of parsing JSON is to parse json string to a known `Codable` JSON structure. But most of the time you may put hand on unknown JSON structures and difficult to define those structures for all scenarios. JSONStore help you to parse JSON in any free form and extract value without constraining into a fixed type. This is pure zero dependency `Swift` package with simplistic `Read Only Until Value Dicovered` design in mind in a single read cycle and theorically should be performant.

## Installation

You can use `Swift Package Manager` to Install `JSONStore` from this repository url. Thats it!

## Usage

> **`warning`** - You need to be 100% sure the input JSON string input is in correct `JSON` format otherwise would give you incorrect or unexpected value.

To access attribute or element you can you a simple `string` path seperated by **`.`** notation.
```swift
import JSONStore

let jsonText = String(data: apiDataBytes, encoding: .utf8)

let nameValue:String = JSONEntity(jsonText).text("properyA.properyB.2") ?? "default value"
```
you can use number to access element in an array
and then use methods. You can use the following methods to access value of given `optional` path
- `text()`
- `array()`
- `bool()`
- `number()`
- `isNull()`
- `isExist()`
- `entries()`

If the key / index does not exist in given path or if the value is another data type from expected formated (except for `text()` see [Exceptions](#exceptional-situations)) then `nill` would be given. You don't need to worry about optional chaining you will recieve `nil` if intermediate path also did not exist.

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
let values = entries[0].value.text() // Sam
```

You can also keep record of intermediate `reference instance` for later use and do chaining.

```swift

let pointer = JSONEntity(jsonText).object("pathA.pathB") // return JSONEntity

let keyValue: String? = pointer.text("pathC.key1")

```
> Note that this would not change reference of `pointer` as `.object()` deliver new `JSONEntity` object.

## Exceptional Situations

- Suppose you access a property like this:
    ```swift
    let value =  JSONEntity(jsonText).text("keyA.keyB.keyC")
    ```
    In JSON data if keyB happens to be an `string` or another primitive type instead of container type of either `object` or `array` then last found intermediete primitive value (in this case string value of keyB) will be return instead of `nil`.

- The result of `.object()` doesn't need necessarily need to be an JSON object but it can be `array` either and you can still access with `.object(somePath).text('2.name')`
- if you are not sure of sure of data type particular of an attribute or `dumping` pourpose you can always use `.text(attributePath)` as it always give the value as a `string` format unless attribute was not found which would give `nil`.

### Author and Main Contributor
@Nishain De Silva