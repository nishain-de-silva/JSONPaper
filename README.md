# JSONStore

Swift is a type constrained lanuage right ? The default way of parsing JSON is to parse json string known `Codable` JSON structure. But most of the time you may put hand on unknown JSON structures still need to access values. Store help you parse JSON in any free form and extract value without constraining into a fixed type. This is pure zero dependency package with simplistic `Read Only Until Value Dicovered` design in mind in a single character-by-character read cycle and theorically should be performant.

## Usage

> **`warning`** - you need to be 100% sure the input JSON string input is in correct `JSON`  format otherwise would give you incorrect or unexpected value.

to access attribute or element you can you a simple `string` path seperated by **`.`** notation.
```swift
import JSONStore

let nameValue:String = JSONEntity(jsonText).text("properyA.properyB.2") ?? "default value"
```
you can use number to access element in an array
and then use methods. You can use the following methods to access value of given `optional` path
- `text()`
- `array()`
- `bool()`
- `number()`
- `isNull()`

If the key does not exist in JSON or in intermediate value or if the value is another data type from expected formated then `nill` would be given. You dont't need to worry about optional chaining

example:
```swift
JSONEntity(jsonText).number("peopple.2.details.age") // return age

JSONEntity(jsonText).number("peopple.2.details.name") // return nil since name is not a number
```

To check if an value is `null` use `isNull()` method don't assume `nil` as `null` it could be value does not exist at all. `isNull` gives `boolean` based on value is actually `null` or or `nil` if value is not found.

### Iterating values

If you need to acesss value is an array you can use:
```swift
guard let hobbies:[JSONEntity] = JSONEntity(jsonText).array("people.2.hobbies") else { return "No hobbies :(" }

hobbies[0].string() // hobby 1
```

You can also keep record intermediate value `instance` for later use.

```swift

let pointer = JSONEntity(jsonText).object("pathA.pathB")

let keyValue: String? = pointerA.text("pathC.key1")

```
> Note that this would not change reference of `pointer` as `.object()` deliver new `JSONEntity` object.

## Exceptional Situations

- Suppose you access a property like this:
    ```swift
    let value =  JSONEntity(jsonText).text("keyA.keyB.keyC")
    ```
    In JSON data if keyB happens to be an `string` or another primitive type instead of container type of either `object` or `array` then last found intermediete primitive value (in this case string value of keyB) will be return instead of `nil`.

- The result of `.object()` doesn't need necessarily need to be an JSON object but it can be `array` either and you can still access with `.object(somePath).text('2.name')`
- if you are not sure of sure of data type particular of an attribute or `debugging` pourpose you can always use `.text(attributePath)` as it always give the value as a `string` format unless attribute was not found which would give `nil`.

### Author and Main Contributor
@Nishain De Silva