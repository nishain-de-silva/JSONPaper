<img src="logo.png" alt="drawing" style="width:100px;"/>

# JSONStore (v2.5) :rocket:

Swift is a type constrained lanuage right ? One way of parsing JSON is to parse JSON string to a known `Codable` JSON structure. In Swift 3 you can use `JSONSerialization` but still you have to chain deserialziation call and it would be mess when you have to check existence of attributes or array values before reading or when handling any complex read queries. Also there are times when expected JSON structure also can have dynamic on certain scenario and would be messy to check value exsistence all the time. JSONStore help you to parse JSON in any free form and extract value without constraining into a fixed type. This is pure zero dependency `Swift` package with `Read Only Until Value Dicovered` mechanism in a single read cycle and performance efficient.

## Installation

You can use `Swift Package Manager` to Install `JSONStore` from this repository url. Thats it!

## Usage

> **Warning**
> The library does `not` handle incorrect `JSON` format. Please make sure to sanatize input string in such cases or otherwise would give you incorrect or unexpected any(s). JSON content must be decodable on `UTF` format (Best tested on `UTF-8` format).
## Intializing

There are handful of ways to initialize JSONStore. You can initialize by `string` or from `Data` instance. Initializing from `Data` is bit trickier as JSONStore does not use `Foundation` so it cannot resolve `Data` type. Hence you have to provide `UnsafeRawBufferPointer` instance instead. You can also provide function which require map callback (eg: `Data.withUnsafeBytes` as constructor parameter _(see [withUnsafeBytes](https://developer.apple.com/documentation/swift/array/withunsafebytes(_:)) to learn about such callbacks)_.

```swift
// with string ...
let jsonAsString = "{...}"
let json = JSONEntity(jsonAsString)

// ways of initilzing with byte data...

let networkData = Data() // your json data

let json = JSONEntity(networkData.withUnsafeBytes) // see simple :)

// or
let bufferPointer: UnsafeRawBufferPointer = networkData.withUnsafeBytes({$0})

let json = JSONEntity(bufferPointer)
```

## Reading Values
To access attribute or element you can you a simple `string` path seperated by dot (**`.`**) notation (or by another custom character with `setSpliter(Character:)`).
```swift
import JSONStore

let jsonText = String(data: apiDataBytes, encoding: .utf8)

let nameValue:String = JSONEntity(jsonText).string("properyA.properyB.2") ?? "default value"
// or
let someValue = entity("propertyA.???.value")
```
- in last example, `???` token represent one or more intermediate dynamic properties before atribute 'value'. In you find more about them in [Intermediate generic properties](#handling-intermediate-dynamic-properties).

you can use number to access element in an array
and then use methods. You can use the following methods to access value of given `optional` path

> when accessing array you can use numbers for indexed items. eg: `user.details.contact.2.phoneNumber`
but don't use any brackets

### Query methods
In all query methods if the key / indexed item does not exist in given path or if the value is another data type from expected formated then `nill` would be given. You don't need to worry about optional chaining you will recieve `nil` if intermediate path also did not exist.

**example**:
```swift
let jsonStore = JSONEntity(jsonText)

jsonStore.number("people.2.details.age") // return age

jsonStore.number("people.2.wrongKey.details.age") // return nil

jsonStore.number("people.2.details.name") // return nil since name is not a number
```

To check if an value is `null` use `isNull()` method don't assume `nil` as `null` it could be value does not exist at all. To be precise use `isNull` which gives `boolean` based on value is actually `null` or `nil` if value entry is not found.

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
## Handling intermediate dynamic properties

There are situations where you have to access a property embedded inside intermediate list of paramters that can change in situations based on JSON response structure.

Imagine from JSON response you recieve json response and you have to fetch the value as on given path,
```swift
let path = "root.memberDetails.currentAcccount.age"
```
but another scenario you have to access age property like this,
```swift
let path = "root.profile.personalInfo.age"
```
This may occur when the application server may provide different `JSON` structure on same `API` call due to different environmental parameters (like user credentials role).
While you use check fail existence of intermediate properties there is a handy way JSONStore use to solve this problem easily.
```swift
let path = "root.???.age"
```
The `???` token is an `intermediate representer` to represent generic **one or more** intermediate path which can be either **object key** or **array index**.
You can customize the `intermediate representer` token with another string with `setIntermediateRepresentor` with another custom string - default token string is `???` (In case if one of the object key also happen to be named `???` !).

You can also use multiple `intermediate representer` tokens like this,
```swift
let path = "root.???.info.???.name"
```

In this way you will get the **first occurence** value that satisy the given dynamic path.

Few rules,
>- Do not use multiple consecutive token in single combo like `root.???.???.value`. Use single token instead as it always can catch more than one intermediates
>- You cannot end a path with an intermediate token (it make sense right, you should at least know what you are searching at the end).


## Handling unknown types

So how do you get value of unknown types ? You can use `any()` method. It gives the natural value of an attribute as a `tuple` containing (value: `Any`, type: `JSONType`).

```swift
let (value, type) = jsonRef.any("somePath")

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

Sometimes you may need to write the results on `serializable` destination such as in-device cache where you have to omit usage of class instances and unwarp its actual value. You can use `parse()` for this, `array` and `object` will be converted to `array` and `dictionary` recursively and other primitive types will be converted in their `natural` values. 

_Remember `null` is represented  by `JSONStore.Constants.NULL`. This is to avoid optional wrapping._

> Be aware that `parse` function procress json content recursively processe on each nested individual `array` and `object` and therefore can cost performance on heavily nested json content.

## Capturing references

`take()` is used to capture the reference of the given path or clone current instance. You can basically query values in 2 ways:

```swift
let value = reference.string(attributePath)!
// or
let value = reference.take(attributePath)?.string()
// both gives same result
```
## Dumping Data

To dump data at a particular node for `debugging` pourpose you can always use `.stringify(attributePath)` as it always give the value in `string` format unless attribute was not found which would give `nil`.

## Author and Main Contributor
@Nishain De Silva

`Thoughts` -   _**"** I recently found out it is difficult parse `JSON` on type constrained lanauage unlike in `JavaScript` so I ended up creating my own library for this pourpose! So I thought maybe others face the same problem and why not make other also have a `taste` of what I created **"**_ :sunglasses:
