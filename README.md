# JSONPond (v2.7) :rocket:
![](https://img.shields.io/badge/Support-Swift-f16430)
![](https://img.shields.io/badge/install-Swift_Package_Manager-f16430)
![](https://img.shields.io/badge/Support-Kotlin-6b6dd7)
![](https://img.shields.io/badge/install-Maven_Central-6b6dd7)


Handling JSON in a type-constrained language ecosystem is a bit tough right? One way of parsing JSON is to parse JSON string to a known object model but you have to know the structure of `JSON` beforehand for this. Also, you may need to chain a lot of calls before being made into the final value plus you might have to check the existence of values and data types of those values when handling any complex read queries. Also, there are times you really need JSON structure to be dynamic in a certain scenario and would be messy to apply safe conditionals all over the code base. Maintaining consistency between the backend response structure and expected reading format is required for all of this perhaps now you need a clean and simpler solution to respond adaptively to different `JSON` outputs.

JSONPond helps you to parse JSON in any free form and extract value without constraining it into a fixed type. This is a pure zero dependency `Swift + Kotlin` library with the technique of `Read Only Need Content` in a single read cycle and which means no byte is read twice! and perfect O(1) time complexity which is why this library is really fast.

## Installation

### Swift

You can use `Swift Package Manager` to Install `JSONPond` from this repository URL. Thats it!

### Kotlin
Gradle script

```groovy
dependencies    {
    implmementation("") // will be added soon...
}

```

## Usage

> **Warning**
> The library does `not` handle or validate incorrect `JSON` format in preference for performance. Please make sure to handle and validate JSON in such cases or otherwise would give you incorrect or unexpected any(s). JSON content must be decodable in `UTF` format (Best tested in `UTF-8` format).
## Initializing

There are a handful of ways to initialize JSONPond. You can initialize by `string` or from the `Data` and `ByteArray` in Swift and Kotlin respectively. In Swift, initializing from `Data` is a bit trickier as JSONPond does not use `Foundation` so it cannot resolve the `Data` type. Hence you have to provide the `UnsafeRawBufferPointer` instance instead. You can also provide a function that requires map callback (eg: `Data.withUnsafeBytes` as constructor parameter _(see [withUnsafeBytes](https://developer.apple.com/documentation/swift/array/withunsafebytes(_:)) to learn about such callbacks)_.

> When initializing from String inner string attributes can be quoted by either single or escaped double quotation you don't have to worry about that!

In Swift,
```swift
// with string ...
let jsonAsString = "{...}"
let json = JSONBlock(jsonAsString)

// ways of initiating with byte data...

let networkData = Data() // your json data

let json = JSONBlock(networkData.withUnsafeBytes) // see simple :)

// or
let bufferPointer: UnsafeRawBufferPointer = networkData.withUnsafeBytes({$0})

let json = JSONBlock(bufferPointer)
```
in Kotlin,
```kotlin
// with string ...
val jsonAsString = "{...}"
val json = JSONBlock(jsonAsString)

// ways of initiating with byte array...

val networkData = Data() // your json data

val json = JSONBlock(byteArray)
```

> Notice that most of the snippets from this documentation are from Swift implementation. You can do the same identical implementation in Kotlin well since most of the API functions have the same name with the same argument signature.

# Reading Data
To access an attribute or element you can provide a simple `String` path separated by dot (**`.`**) notation (or by another custom character with `splitQuery(Character:)`).
```swift
import JSONPond

let jsonText = String(data: apiDataBytes, encoding: .utf8)

let nameValue:String = JSONBlock(jsonText).string("properyA.properyB.2") ?? "default value"
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
let JSONPond = JSONBlock(jsonText)

JSONPond.number("people.2.details.age") // return age

JSONPond.number("people.2.wrongKey.details.age") // return nil

JSONPond.number("people.2.details.name") // return nil since name is not a number
```

To check if a value is `null` use the `isNull()` method. JSONPond always gives `nil` / `null` when the attribute is missing or when the data type of the value does not match with the expected datatype, **not** when an attribute is representing a JSON null value.

```swift
let stringArray = entity.array("pathToArray.studentNames").map({ item in
    // item is a JSONBlock instance
    return item.string() 
})

```
## Approximate attribute matching

As said before JSONPond is good at handling unknown JSON structures which means in situations you sometimes know the attribute name to search for but you are not sure about case-sensitivity or special characters involved eg: you know about an attribute with the name `studentId` but not sure if its actually `studentID` or `student_Id` or `student-ID`. In every query function, there is `similarKeyMatch` optional boolean parameter whether to match attribute names in case-insensitive behavior **and** ignore all non-alphanumeric characters.

### Check value existence

You can use `isExist(:path)` to test if a element given on the path exists, alternatively you can use `isExistThen(:path)` if you want to chain based on the result.
```swift
// normal conditional use
if entity.isExist("somePath") {
    // do some work
}
// or chain based on condition
guard let newEntity = entity.isExistThen("testPath")?.push("testPath", "new value") else {
    print("error - path does not exist")
    return
}
```
## Parsing data types

For every read query methods you can parse string values into their respective JSON value by using the `ignoreType` parameter (default `false`).
- for `boolean` and `null` the string values must be `"true"`, `"false"` and `null` (lower-case) only.
- When parsing `object` and `array` the nested delimiter which is automatically detected can be either by single or double quotes.

```json
{
    "pathA": {
        "numString": "35"
    },
    "sampleData": "{'inner': 'awesome'}",
    // or 
    "sampleData": "{\"inner\": \"awesome\"}"
}
```

```swift
 let value = jsonReference.number("pathA.numString") // return nil

 let value = jsonReference.number("pathA.numString", ignoreType = true) // return 35

 let value = jsonReference.objectEntry("sampleData", ignoreType = true).string("inner") // return awesome
```
## Iterating arrays and objects

Not only arrays you also need to iterate through JSON objects as well. Using `collection(:path)` function you iterate from either array or object so you don't which will give an array of `JSONChild`. `JSONChild` has additional 2 fields named `index` and `key` where `key` get populated when iterating on an object and`index` value is populated on array iteration representing position index.

```swift
let collection :[JSONChild] = source.collection("pathA.pathToCollection")

collection?.map({
    // on object enumeration
    if $0.index == -1 {
        print($0.key)
    } else {
        // on array enumeration
        print($0.index)
    }
    // JSONChild is a sub-class JSONBlock
    print($0.parse())
})
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
You can customize the `intermediate representer` token with another string with `setIntermediateToken` with another custom string - the default token string is `???` (In case one of the object attributes also happen to be named `???` !).

You can also use multiple `intermediate representer` tokens like this,
```swift
let path = "root.???.info.???.name"
```

In this way, you will get the **first occurrence** value that satisfies the given dynamic path. If you want to collect all attributes that satifies the path then use `all(:path)`.

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
.object | JSONBlock
.array | [JSONBlock]
.null | `JSONPond.Constants.NULL`

you could additionally use `type()` to get the data type of the current JSON `reference`.

## Serializing Data

Sometimes you may need to write the results on a `serializable` destination such as an in-device cache where you have to omit the usage of class instances and unwarp its actual value. You can use `parse()` for this, `array` and `object` will be converted to `array` and `dictionary` recursively until reaching primitive values of boolean, numbers, and null.

_Remember `null` is represented by `JSONPond.Constants.NULL`. This is to avoid optional wrapping._

# Writing Data
JSONPond now supports the entire CRUD functionality. For write operations, there are 4 functions.
- `delete()`
- `replace()`
- `push()`
- `replaceOrPush()`

To write JSON from scratch use the static method `JSONBlock.write()` method,

In Swift,
```swift

JSONBlock.write([
    "person": [
        "name": "Joe smith",
        "age": 26,
        "hobbies": ["coding", "gaming"],
        "Education": [
            "graduated": true,
            "school": "Oxford",
            "otherDetails": nil
        ]
    ]
]) // see easy peasy...
```

In Kotlin,
```kotlin
JSONBlock.write(mapOf(
    "person" to mapOf(
        "name" to "Joe smith",
        "age" to 26,
        "hobbies" to listOf("coding", "gaming"),
        "Education" to mapOf(
            "graduated" to true,
            "school" to "Oxford",
            "otherDetails" to null
        )
    )
))
```
> In Kotlin, when defining array type attribute always use `listOf()` instead of `arrayOf()`.

All write functions are chainable which allows you to execute mutliple write functions which updates the same instance in the order of the chain. When a write function fail it will execute one time error callback which provided to `onQueryFail(errorHandler:)` function.The callback will only will execute only once and expire after completing the proceeding write operation.

The `push()` function is used for both adding key attributes for objects as well as appending items to the array. In `push()` ending path should contain the name of the attribute when pushing to an object or specify the index when pushing to an array. If you just want to push to the end of the array just include a non-existent index like `-1`.
```swift
let sampleData = [
    "sample": [
        "nestedData": [34, 55]
    ]
]
// for objects - path to object + new key
let keyPath = "pathA.PathB.targetObject.newKey"
entity.push(keyPath, sampleData)

// for arrays - only specify the path to the array
let arrayPath = "pathA.PathB.targetArray"
entity.push(arrayPath, sampleData)
```

> **Warning**
> Write query functions do not support intermediate `???` tags. You should be aware of the absolute path you want to write or delete.

## Update and replaceOrPush

In the `replace()` method, you generally give the full path to the target element and data to fully replace with. In `replaceOrPush` if the key or array item is not found to update then a new element will be added addressed object or array.

```swift
let entity.replaceOrPush("members.0.residentPlace", "Madagascar")

let entity.replaceOrPush("members.0.hobbies.3", "bird watching")
```
- first example
> If the `residentPlace` attribute exists it would be updated by a new value or residentPlace will be added as a new key with the newly assigned value.

- second example

> If a member only has 3 hobbies but since index 3 does not exist it would add another item to the hobbies array or else update the fourth item if it exists.

Basically `push()` and `replace()` are constrained versions of `replaceOrPush()`. Insert operation only works if the key or index does not exist and `replace()` works only for existing key or array index.

### Delete node

You can use `delete()` of course to delete an item on a given path if the item exists.

### Reading bytes

After all of these write operations you can receive the output as bytes in terms of `[Uint8]` or `ByteArray` or you can `optionally` pass a map function to customize the output with a generic type.

In Swift example,
```swift
let response: Data = entity.replace("members.2.location.home", "24/5 backstreet malls").bytes({Data($0)})


```



## Capturing references

`capture()` is used to capture the `JSONBlock` reference of the given path. You can query values in 2 ways:

```swift
let value = reference.string(attributePath)!
// or
let value = reference.capture(attributePath)?.string()
//Both give the same result
```

## Error Listeners

JSONPond also allows adding a fail listener before calling a read or write a query to catch possible errors. Error callback gives you a object consisting of 3 values: 
- The error code
- Index of the query fragment where the issue has been detected from the query path.
- query path which error has occured.

In the below example if the field `name` is actually a `string` instead of a nested `object` then JSONPond will give you an error

```swift
let result = entity
    .onQueryFail({
        print($0.explain())
    })
    .replace(
        "user.details.name.first", "Joe"
    )
    .stringify()

```
would give you an output:
```
[nonNestedParent] occurred on query path (user.details.name.first)
        At attribute index 2
        Reason: intermediate parent is a leaf node and non-nested. Cannot transverse further
{
    "user": {
        "details": {
            "name": "Bourne Smith"
        }
    }
}
```
So it indicates the error happen on index 2 which means the "name" segment in the query and the error itself is an enum value like in here - `ErrorCode.nonNestedParent`. You can use these enum constants to catch a specific type of error.

### Bubbling errors from child nodes

In default behavior `JSONPond` instance look for a fresh error handler when an error got invoked and if there is no error handler it would ignore the error and return `nil `/ `null` nevertheless. This is most of the time not an issue but what happens if you use a call that returns fresh inline `JSONPond` instances?

```swift
let result = entity
    .onQueryFail({
        // error handler will not work
        print($0.explain())
    })
    .capture("user") // this call generate fresh instance
    .replace(
        "details.name.first", "Joe"
    ) // error discarded as no error callback defined on the current instance
    .stringify()
```
let result = entity
You can either provide `onFail` callback just before calling `.replace()` or enable the `bubbling` parameter on the top-level `onQueryFail` callback,
```swift
let result = entity
    .onQueryFail({
        // error handler will not work
        print($0.explain())
    }, bubbling: true)
    .capture("user") // bottom error will be forwarded to top
    .replace(
        "details.name.first", "Joe"
    )
    .stringify()
```
this will make errors invoked under the child element escalate to the top level unless error handler unless you explicitly define an error handler on one of the child nodes on their own which would break the bubbling chain.

## Dumping Data

To visually view data at a particular node for `debugging` purposes you can always use `.stringify(attributePath)` as it always gives the value in `string` format unless the attribute was not found which would give `nil`.

If you find this library useful and got impressed please feel free to like this library so I would know people love this! :heart:

## Author and Main Contributor
@Nishain De Silva

`Thoughts` -   _**"** I recently found out it is difficult to parse `JSON` on type-constrained language unlike in `JavaScript` so I ended up inventing a library for my purpose! So I thought maybe others face the same problem and why not make others also have a `taste` of what I created and keep on adding more features to make JSON reading with less hassle.**"**_ :sunglasses:

## FAQ

**What is the differance between using `capture()` and `any()` ?**

While it is tempting to think both give result irrespective of data type `any()` gives the natural of the node meaning if it is a boolean then it would give either true or false while `capture()` deliver wrapped value as `JSONBlock`.

**When to use `parse()` and why it is distinguished from `any()` method ?**

Both intend to give natural value but `parse()` extends beyond `any()` when giving natural value. Both give the same output when it comes to singular values (string, boolean, null, and numbers)  but when it comes to objects and arrays `any()` still delivers values wrapped in `JSONBlock` but `parse()` recursively add `dictionary` and `array`. So in general, `any()` is used is same as calling to other read query method but without knowing the data type, and `parse()` is used for serialization purposes and to deliver serialized data and handle them with native types only (`Array` `Dictionary`, `String` .etc)

**After dicovering a instance is iterable with `type()` how to iterate it afterwards ?**

You can `collection(:path)` without the `path` parameter which would give all child elements within itself. If you want to filter elements that contain specific sub-path you can use the `all()` method instead.