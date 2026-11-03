import Testing
@testable import ElemelekCore

@Suite struct ListLeadsTests {
    @Test func newsletterListGetsLeads() {
        let items = [
            "Google Play googleplay-noreply@google.com — Your Google Play Order Receipt (nic do zrobienia)",
            "Onet Premium newsletter@grupaonet.pl — Wraca tajemnicza sprawa (nieaktualne)",
            "Manchester City: 114 z 115 zarzutów, grozi degradacja",
            "24-latka straciła macicę; profesor dzwonił do patomorfologa",
        ]
        let leads = ListLeads.detect(in: items)
        #expect(leads[0] == "Google Play googleplay-noreply@google.com".count)
        #expect(leads[1] == "Onet Premium newsletter@grupaonet.pl".count)
        #expect(leads[2] == "Manchester City".count)
        #expect(leads[3] == nil)
    }

    @Test func shoppingListHasNone() {
        #expect(ListLeads.detect(in: ["mleko", "chleb", "zadzwon do mamy"]) == [nil, nil, nil])
    }

    @Test func shortListNeverQualifies() {
        #expect(ListLeads.detect(in: ["Onet: wraca sprawa", "Google: paragon"]) == [nil, nil])
    }

    @Test func sentenceBeforeDashIsNotALead() {
        #expect(ListLeads.leadLength(in: "Nowe limity podatkowe na 2027 r. — ryczałtowcy mogą stracić") == nil)
        #expect(ListLeads.leadLength(in: "Myślałem o tym bardzo długo i w końcu, po wielu godzinach namysłu — poszedłem") == nil)
    }

    @Test func numericLeadIsNotALead() {
        #expect(ListLeads.leadLength(in: "12:30 — spotkanie w sali") == nil)
    }

    @Test func danglingSeparatorHasNoLead() {
        #expect(ListLeads.leadLength(in: "Nagłówek — ") == nil)
        #expect(ListLeads.leadLength(in: "Samo zdanie bez separatora") == nil)
    }

    @Test func sparseMatchesLeaveListAlone() {
        let items = ["Onet: wraca sprawa", "zwykły tekst", "inny zwykły tekst", "jeszcze inny", "ostatni"]
        #expect(ListLeads.detect(in: items) == [nil, nil, nil, nil, nil])
    }

    @Test func longMixedListMarksItsLeadRun() {
        let items = [
            "ISW Publications publications@x.or — Iran Update (nic do zrobienia)",
            "Huti wycofali się spod Mochy po ostrzale",
            "Wrzesień 2026: dochody niższe o 10 mld",
            "Siły saudyjskie uderzyły na bazę Al Omari",
            "Podcast: czy sojusznik jest poczytalny",
            "Ukraińskie uderzenia wyłączyły ponad połowę mocy rafineryjnych",
            "Kontrole ZUS: dr Szymon o podejrzeniach",
            "W nocy Rosja wystrzeliła 137 dronów na Ukrainę",
            "Manchester City: 114 z 115 zarzutów",
            "24-latka straciła macicę; profesor dzwonił do patomorfologa",
            "Onet Premium x@y.pl — Wraca sprawa (nieaktualne)",
            "Sędzia, który dał list żelazny, chwalił Brauna",
        ]
        let leads = ListLeads.detect(in: items)
        #expect(leads[0] == "ISW Publications publications@x.or".count)
        #expect(leads[2] == "Wrzesień 2026".count)
        #expect(leads[4] == "Podcast".count)
        #expect(leads[6] == "Kontrole ZUS".count)
        #expect(leads[8] == "Manchester City".count)
        #expect(leads[10] == "Onet Premium x@y.pl".count)
        #expect(leads[1] == nil && leads[3] == nil && leads[5] == nil)
        #expect(leads[7] == nil && leads[9] == nil && leads[11] == nil)
    }

    @Test func thinRunInLongListLeavesItAlone() {
        var items = [
            "Onet: wraca sprawa",
            "Google: paragon",
            "Podcast: nowy odcinek",
            "ZUS: kontrole",
        ]
        items += ["zwykły tekst", "inny zwykły tekst", "jeszcze inny", "ostatni",
                  "kolejny", "przedostatni", "zupełnie zwykły", "koniec"]
        #expect(ListLeads.detect(in: items) == [Int?](repeating: nil, count: items.count))
    }

    @Test func pipeSeparatorWorks() {
        #expect(ListLeads.leadLength(in: "Źródło | nagłówek dnia") == "Źródło".count)
    }

    @Test func longerEventNameStillALead() {
        let lead = "Warsztat Sentry o debugowaniu agentów na produkcji"
        #expect(lead.count == 50)
        #expect(ListLeads.leadLength(in: lead + " — 14 października") == 50)
    }
}
