import Testing
@testable import SkillsManager

struct SkillsDirectoryServiceTests {
    @Test
    func fallbackIgnoresExtraSkillsShEntryFields() async {
        let html = #"""
        <script>self.__next_f.push([1,"47:{\"source\":\"vercel-labs/skills\",\"skillId\":\"find-skills\",\"name\":\"find-skills\",\"installs\":2377324,\"weeklyInstalls\":[122605,116561],\"metadata\":{\"official\":true}}"])</script>
        <script>{"source":"anthropics/skills","skillId":"frontend-design","name":"frontend-design","installs":633931,"weeklyInstalls":[31956,31670],"metadata":{"official":true}}</script>
        <span>"totalSkills":9593</span>
        """#

        let result = await SkillsDirectoryService().parseSkillsDirectoryHTML(html)

        #expect(result.total == 9593)
        #expect(result.skills.map(\.id) == [
            "vercel-labs/skills:find-skills",
            "anthropics/skills:frontend-design"
        ])
        #expect(result.skills.first?.installCommand == "npx skills add https://github.com/vercel-labs/skills --skill find-skills")
    }
}
