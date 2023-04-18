import org.junit.Test
import java.io.File

class JSONPondTest {
    @Test
    fun startTest() {
        val fileName = "test2.json"
        val data = File("./src/test/swift/$fileName").readBytes()
//        val entity = JSONEntity(data)
//        entity.onQueryFail { error, querySegmentIndex -> println(error.describe()) }
        val result = JSONPond.write(mapOf(
            "name" to mapOf(
                "first" to "nishain",
                "last" to "de silva"
            ),
            "age" to Null,
            "hobbies" to listOf("first", "second", listOf<String>())
        ))
        result.insert("hobbies.2.0", "walking")
        println(result.stringify())
    }
}