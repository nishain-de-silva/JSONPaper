import com.jsonpond.JSONBlock
import org.junit.Test
import java.io.File

class JSONBlockTest {
     @Test
    fun startTest() {
        val fileName = "demonstration.json"
        val data = File("./src/test/swift/$fileName").readBytes().decodeToString()

        val pond = JSONBlock(data)
        val result = pond.onQueryFail({
            println(it.explain())
        }, bubbling = true)
            .collection("details.???.printable")?.first()
         println("result: $result")
    }
}