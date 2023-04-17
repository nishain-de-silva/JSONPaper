<img src="logo.png" alt="drawing" style="width:100px;"/>

# JSONPond (v2.6) :rocket:

Swift, is a type of constrained language right? One way of parsing JSON is to parse JSON string to a known `Codable` JSON structure. In Swift 3 you can use `JSONSerialization` but still, you have to chain deserialization calls and it would be a mess when you have to check the existence of attributes or array values before reading or when handling any complex read queries. Also, there are times when the expected JSON structure also can have dynamic in a certain scenario, and would be messy to check the existence of value all the time. JSONPond help you to parse JSON in any free form and extract value without constraining it into a fixed type. This is a pure zero dependency `Swift` package with the technique of `Read Only Need Content` in a single read cycle and which means no byte is read twice! which is why this library is really fast.

## Installation

You can use `Swift Package Manager` to Install `JSONPond` from this repository URL. Thats it!

## Usage

> **Warning**
> The library does `not` handle or validate incorrect `JSON` format in preference for performance. Please make sure to handle and validate JSON in such cases or otherwise would give you incorrect or unexpected any(s). JSON content must be decodable in `UTF` format (Best tested in `UTF-8` format).
## Initializing

There are a handful of ways to initialize JSONPond. You can initialize by `string` or from the `Data` instance. Initializing from `Data` is a bit trickier as JSONPond does not use `Foundation` so it cannot resolve the `Data` type. Hence you have to provide the `UnsafeRawBufferPointer` instance instead. You can also provide a function that requires map callback (eg: `Data.withUnsafeBytes` as constructor parameter _(see [withUnsafeBytes](https://developer.apple.com/documentation/swift/array/withunsafebytes(_:)) to learn about such callbacks)_.

```swift
// with string ...
let jsonAsString = "{...}"
let json = JSONEntity(jsonAsString)

// ways of initiating with byte data...

let networkData = Data() // your json data

let json = JSONEntity(networkData.withUnsafeBytes) // see simple :)

// or
let bufferPointer: UnsafeRawBufferPointer = networkData.withUnsafeBytes({$0})

let json = JSONEntity(bufferPointer)
```

# Reading Data
To access an attribute or element you can provide a simple `String` path separated by dot (**`.`**) notation (or by another custom character with `splitQuery(Character:)`).
```swift
import JSONPond

let jsonText = String(data: apiDataBytes, encoding: .utf8)

let nameValue:String = JSONEntity(jsonText).string("properyA.properyB.2") ?? "default value"
// or
let someValue = entity("propertyA.???.value")
```
> **note**
> You can temporarily make your next query string get split by a custom character you give in `splitQuery(by:)`. This is to evade situations where the object key/attribute also happens to have dot `(.)` notation in their name.
- In the last example, the `???` token represents zero or more intermediate dynamic properties before the attribute 'value'. You can find more about them in [Intermediate generic properties](#handling-intermediate-dynamic-properties).

You can use a numeric index to access an element in an array
in place of an attribute in a nested object. for example:
```swift
/* when accessing an array you can use numbers for indexed items */

let path = "user.details.contact.2.phoneNumber"
```

> Your element index may be out of bound from the observed array and hence return `nil` in such cases


### Query methods
In all query methods if the key / indexed item does not exist in the given path or if the returned value has a data type different from the expected data type then `nil` would be given. You don't need to worry about optional chaining you will receive `nil` when the intermediate path also does not exist.

**Example**:
```swift
let JSONPond = JSONEntity(jsonText)

JSONPond.number("people.2.details.age") // return age

JSONPond.number("people.2.wrongKey.details.age") // return nil

JSONPond.number("people.2.details.name") // return nil since name is not a number
```

To check if a value is `null` use the `isNull()` method. Don't assume `nil` as `null` as it could be also that value you expect does not exist at all. Instead, you can use `isNull` which returns a `boolean` if the value is actually `null`.

Calling query methods by omitting the `path` parameter will extract the value in the current instance and return it to the relevant data type or `nil` if the content is in another data type.

```swift
let stringArray = entity.array("pathToArray.studentNames").map({ item in
    // item is a JSONEntity instance
    return item.string() 
})
```
### Check value existence

You can use `isExist(:path)` which will give either return boolean or an optional reference to the current instance if the path exists. In other words, you can,
```swift
// normal conditional use
if entity.isExist("somePath") {
    // some work
}
// or chain based on condition
entity.isExist("somePath")?.stringify()
```
## Parsing data types

For `number`, `boolean`, `object`, and `array` query methods you can parse these values from JSON string by using the `ignoreType` parameter (default `false`)
- for booleans, the string values must be `"true"` or `"false"` (case-sensitive) only.
- When parsing `object` and `array` the JSON string should use `escaped` double quotation (`not` single quotations) - **`\"`** for string terminators. Of course, you have to make sure the string is a valid JSON as well.

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

There are situations where you have to access a child embedded inside an intermediate list of nested objects and arrays that can change based on situations on JSON response structure.

Imagine from JSON response you receive a JSON response in which you have to fetch the value on the given path,
```swift
let path = "root.memberDetails.currentAcccount.age"
```
but in another scenario, you have to access age property like this,
```swift
let path = "root.profile.personalInfo.age"
```
This may occur when the application server may provide a different `JSON` structure on the same `API` call due to different environmental parameters (like user credentials role).
While it is possible to check the existence of intermediate properties conditionally there is a handy way JSONPond use to solve this problem easily.
```swift
let path = "root.???.age"
```
The `???` token is an `intermediate representer` to represent generic **zero or more** intermediate paths which can be either **object key** or **array index**.
You can customize the `intermediate representer` token with another string with `setIntermediateRepresent` with another custom string - the default token string is `???` (In case one of the object attributes also happen to be named `???` !).

You can also use multiple `intermediate representer` tokens like this,
```swift
let path = "root.???.info.???.name"
```

In this way, you will get the **first occurrence** value that satisfies the given dynamic path.

Few rules,
>- Do not use multiple consecutive tokens in a single combo like `root.???.???.value`. Use a single token instead.
>- You cannot end a path with an intermediate token (it makes sense right, you should at least know what you are searching for at the end).


## Handling unknown types

So how do you get the value developer initially without knowing its type? You can use the `any()` method. It gives the natural value of an attribute as a `tuple` containing (value: `Any`, type: `JSONType`).

```swift
let (value, type) = jsonRef.any("somePath")

if type == .string {
    // you can safely downcast to string
} else if type == .object {
    // if object...
} // and so on...

```

type  | output
--- | ---
.string | string
.number | double
.boolean | `true` or `false`
.object | JSONEntity
.array | [JSONEntity]
.null | `JSONPond.Constants.NULL`

you could additionally use `type()` to get the data type of the current JSON `reference`.

## Serializing Data

Sometimes you may need to write the results on a `serializable` destination such as an in-device cache where you have to omit the usage of class instances and unwarp its actual value. You can use `parse()` for this, `array` and `object` will be converted to `array` and `dictionary` recursively until reaching primitive values of boolean, numbers, and null.

_Remember `null` is represented by `JSONPond.Constants.NULL`. This is to avoid optional wrapping._

# Writing Data
JSONPond now supports the entire CRUD functionality. For write operations, there are 4 functions.
- `delete()`
- `update()`
- `insert()`
- `upsert()`

To write JSON from scratch use the static method `JSONEntity.write()` method,

```swift

JSONEntity.write([
    "person": [
        "name": "Joe smith",
        "age": 26,
        "hobbies": ["coding", "gaming"],
        "Education": [
            "graduated": true,
            "school": "Oxford",
            "otherDetails": Constants.NULL
        ]
    ]
]) // see easy peasy...

```
> JSONPond has a global constant with the name `Null` as an alias for the enum `Constants.NULL` you can use that as well!

Write functions made it easy to return the instance that has been written you continue the rest of the work in the chain. When a write function failed JSONPond would provide an error message to find out where in the query did write function specifically failed.

The `insert()` function is used for both adding key attributes for objects as well as appending items to the array. If you set a new attribute or indexed value for an object or array respectively then your path should be:
```swift
let sampleData = [
    "sample": [
        "nestedData": [34, 55]
    ]
]
// for objects - path to object + new key
let keyPath = "pathA.PathB.targetObject.newKey"
entity.insert(keyPath, sampleData)

// for arrays - only specify path to array
let arrayPath = "pathA.PathB.targetArray"
entity.insert(arrayPath, sampleData)
```

> **Warning**
> write query functions do not support intermediate `???` tags. You should be aware of the absolute path you want to write or delete.

## Update and Upsert

In the `update()` method, you generally give the full path to the target element and data to fully replace with. In `upsert` if the key or array item is not found to update then a new element will be added addressed object or array.

```swift
let entity.upsert("members.0.residentPlace", "Madacascar")

let entity.upsert("members.0.hobbies.3", "bird watching")
```
- first example
> if the `residentPlace` attribute exists it would be updated by a new value or residentPlace will be added as a new key with the newly assigned value.

- second example

> If a member only has 3 hobbies but since index 3 does not exist it would add another item to the hobbies array or else update the fourth item if it exists.

Basically `insert()` and `update()` are constrained versions of `upsert()`. Insert operation only works if the key or index does not exist and `update()` works only for existing key or array index.

### Delete node

You can use `delete()` of course to delete an item on a given path if the item exists.

### Reading bytes

After all of these write operations you can receive the output as bytes in terms of `[Uint8]` or you can `optionally` pass a map function to customize the output with a generic type.

```swift
let response: Data = entity.update("members.2.location.home", "24/5 backstreet malls").bytes({Data($0)})


```



## Capturing references

`capture()` is used to capture the `JSONEntity` reference of the given path. You can query values in 2 ways:

```swift
let value = reference.string(attributePath)!
// or
let value = reference.capture(attributePath)?.string()
// both give the same result
```

## Error Listeners

JSONPond also allows adding a fail listener before calling a read or write a query to catch possible errors. Error callback gives you a tuple consisting of 2 values: 
- The error code
- Index of the query fragment where the issue has been detected from the query path.
In the below example if the field `name` is actually a `string` instead of a nested `object` then JSONPond will give you an error

```swift
let result = entity
    .onQueryFail({
        print($0.error.describe())
        print("occurred on the index:", $0.querySegmentIndex)
    })
    .update(
        "user.details.name.first", "Joe"
    )
    .stringify()

```
would give you an output:
```
[nonNestedParent] intermediate parent is a leaf node and non-nested. Cannot transverse further
occurred on the index: 2
{
    "user": {
        "details": {
            "name": "Bourne Smith"
        }
    }
}
```
So it indicates the error happen on index 2 which means the "name" segment in the query and the error itself is an enum value `ErrorCode.nonNestedParent`. You can use these enum constants to catch a specific type of error.

## Dumping Data

To visually view data at a particular node for `debugging` purposes you can always use `.stringify(attributePath)` as it always gives the value in `string` format unless the attribute was not found which would give `nil`.

If you find this library useful and got impressed please feel free to like this library so I would know people love this! :heart:

## Author and Main Contributor
@Nishain De Silva

`Thoughts` -   _**"** I recently found out it is difficult to parse `JSON` on type-constrained language unlike in `JavaScript` so I ended up inventing a library for my purpose! So I thought maybe others face the same problem and why not make others also have a `taste` of what I created and keep on adding more features to make JSON reading with less hassle.**"**_ :sunglasses:
