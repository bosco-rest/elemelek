import Testing
@testable import ElemelekCore

@Suite struct SectionHeaderTests {
    @Test func labelsEndingWithColonAreHeaders() {
        #expect(SectionHeader.isHeader("Zarchiwizowane (1):"))
        #expect(SectionHeader.isHeader("nowszy mail w tej samej sprawie — 1:"))
        #expect(SectionHeader.isHeader("A oto wyniki:  "))
    }

    @Test func plainLinesAreNotHeaders() {
        #expect(!SectionHeader.isHeader("Nowe do zrobienia"))
        #expect(!SectionHeader.isHeader("Ala ma kota."))
        #expect(!SectionHeader.isHeader("No"))
    }

    @Test func multilineOrOversizedLinesAreNotHeaders() {
        #expect(!SectionHeader.isHeader("Pierwsza linia\nDruga:"))
        #expect(!SectionHeader.isHeader(String(repeating: "słowo ", count: 30) + ":"))
    }
}
