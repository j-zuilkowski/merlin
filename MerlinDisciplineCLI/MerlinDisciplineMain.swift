import Foundation

@main
struct MerlinDisciplineMain {
    static func main() async {
        let code = await DisciplineCLI.run(arguments: CommandLine.arguments)
        exit(code)
    }
}
