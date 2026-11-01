import Testing
@testable import Splt

@Suite("CSV text")
struct CSVTextTests {
    @Test func readsSimpleRows() {
        #expect(CSVText.rows("a,b,c\n1,2,3\n") == [["a", "b", "c"], ["1", "2", "3"]])
    }

    @Test func readsQuotedFieldsWithCommasQuotesAndLineBreaks() {
        let text = "title,note\n\"Dinner, with friends\",\"said \"\"hi\"\"\nthen left\"\n"
        #expect(CSVText.rows(text) == [["title", "note"], ["Dinner, with friends", "said \"hi\"\nthen left"]])
    }

    @Test func handlesWindowsLineEndingsBlankLinesAndABOM() {
        #expect(CSVText.rows("\u{FEFF}a,b\r\n\r\n1,2\r\n") == [["a", "b"], ["1", "2"]])
    }

    @Test func keepsEmptyFieldsAndTheLastRowWithoutANewline() {
        #expect(CSVText.rows("a,,c\n,,") == [["a", "", "c"], ["", "", ""]])
    }

    @Test func writesAndReadsBackTrickyFields() {
        let fields = ["plain", "with,comma", "with \"quote\"", "two\nlines", ""]
        #expect(CSVText.rows(CSVText.line(fields)) == [fields])
    }

    @Test func formulaLookingTextIsNeutralizedAndRestored() {
        for text in ["=SUM(A1)", "+1", "-2", "@cmd"] {
            let safe = CSVText.neutralized(text)
            #expect(safe.hasPrefix("'"))
            #expect(CSVText.restored(safe) == text)
        }
        #expect(CSVText.neutralized("Dinner") == "Dinner")
        #expect(CSVText.restored("'quoted") == "'quoted")
    }
}
