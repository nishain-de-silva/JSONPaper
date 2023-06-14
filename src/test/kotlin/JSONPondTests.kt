import JSONPond.JSONBlock
import org.junit.Test
import java.io.File

class JSONBlockTest {
     @Test
    fun startTest() {
        val fileName = "test2.json"
        val data = File("./src/test/swift/$fileName").readBytes().decodeToString()

        val pond = JSONBlock(data)
        val result = pond.onQueryFail({
            println(it.explain())
        }).all("..root.???..temperature").forEach { it.string("fjkndf") }
         println(result)
//        val result = pond.onQueryFail { error, querySegmentIndex -> println("$querySegmentIndex ${error.describe()}") }
//            .all("root.???.listenedon",true).map { it.parse() }
//         println(result)
    }
}