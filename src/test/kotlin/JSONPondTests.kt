import com.jsonpond.JSONBlock
import org.junit.Test
import java.io.File

class JSONBlockTest {
     @Test
    fun startTest() {
        val fileName = "large-file.json"
        val data = File("./src/test/swift/$fileName").readBytes().decodeToString()

        val pond = JSONBlock(data)
        val result = pond.onQueryFail({
            println(it.explain())
        })
            .string("11350..id")
         println(result)
    }
}