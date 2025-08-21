import Foundation

// MARK: - FlipPage Model
struct FlipPage: Codable, Identifiable {
    let id = UUID()
    let type: PageType
    var title: String?
    var caption: String?
    var text: String? // Full text content for text pages
    var imageBase64: String?
    var imageName: String?
    
    enum PageType: String, Codable, CaseIterable {
        case cover = "cover"
        case leftBars = "leftBars" // Legacy - use 'text' instead
        case text = "text" // Text content page
        case rightPhoto = "rightPhoto"
        case mixed = "mixed"
        case html = "html"
    }
    
    init(type: PageType, title: String? = nil, caption: String? = nil, text: String? = nil, imageBase64: String? = nil, imageName: String? = nil) {
        self.type = type
        self.title = title
        self.caption = caption
        self.text = text
        self.imageBase64 = imageBase64
        self.imageName = imageName
    }
}

// MARK: - Sample FlipPages with Rich Content (Emotionally Resonant Preview)
extension FlipPage {
    static let samplePages: [FlipPage] = [
        // Cover page - Making it more emotionally compelling
        FlipPage(type: .cover, title: "Our Family Legacy", caption: "Stories Worth Preserving"),
        
        // Story 1: Grandma's Secret Recipe - A story about food as family heritage
        // IMAGE PROMPT 1: "Warm 1950s kitchen, grandmother's hands kneading dough, soft morning light through lace curtains, vintage apron, flour dust in sunbeams, nostalgic photography style"
        // IMAGE PROMPT 2: "Multi-generational family gathered around Thanksgiving table, warm candlelight, vintage china, everyone laughing, documentary style photography, golden hour lighting"
        FlipPage(type: .text, title: "Grandma's Secret Recipe", text: """
        Every family has that one recipe—the one that appears at every gathering, carrying with it the weight of generations. For us, it was Grandma's apple pie. But the story behind it was far richer than any filling.
        
        "This recipe," Grandma would say, her weathered hands moving with practiced precision, "came across the ocean in my mother's memory. No paper, just here," she'd tap her temple, "and here," placing her hand over her heart.
        
        It was 1923 when my great-grandmother arrived at Ellis Island with three children, a worn suitcase, and this recipe—one of the few pieces of home she could carry. The ingredients were simple: apples, sugar, cinnamon, and butter. But the secret, Grandma insisted, was in the love.
        
        During the Depression, when apples were sometimes all they had, this pie became a symbol of abundance even in scarcity. "We may not have much," Great-grandma would say, "but we can always make something beautiful from what we have."
        
        I remember standing on a wooden stool in Grandma's kitchen, barely tall enough to see over the counter. She'd guide my small hands, teaching me to feel when the dough was just right. "Too much flour and it's tough, too little and it falls apart. Like life, finding balance is everything."
        
        The kitchen would fill with the scent of cinnamon and baking apples, drawing family members like a lighthouse draws ships. Uncle Tony would appear first, always claiming he was "just passing by." Then Aunt Maria, then the cousins, until the small kitchen overflowed with laughter and stories.
        
        Grandma would tell us about the first time she made the pie for Grandpa. "I was so nervous, I forgot the sugar! But he ate every bite, smiled, and said it was perfect. That's when I knew he was the one."
        
        When Grandma's hands began to tremble with age, she called me to her kitchen one last time. "It's your turn now," she said simply. We made the pie together, her guiding voice replacing her steadying hands. She shared the final secret: a pinch of cardamom, "for the old country," and a tablespoon of cream, "for the new."
        
        Now, when I make this pie for my own grandchildren, I tell them this story. I show them how to feel the dough, how to layer the apples just so, how to crimp the edges with love. The recipe has evolved—we have better ovens, fresher ingredients—but the essence remains unchanged.
        
        This pie is more than dessert. It's our history, baked golden brown. It's the courage of a young woman crossing an ocean, the resilience of a family through hard times, the love story of my grandparents, and now, the legacy I pass on. Each bite carries the flavor of five generations, seasoned with stories and sweetened with memory.
        
        Some inheritances come in the form of money or property. Mine came as flour-dusted hands, patient teaching, and a recipe that means home, no matter where in the world I am.
        """),
        
        // Family kitchen photo for Story 1
        FlipPage(type: .rightPhoto, title: "Kitchen Memories", caption: "Where recipes became rituals and kitchens became classrooms.", imageName: "family_kitchen"),
        
        // Story 2: Dad's Workshop Wisdom - Life lessons through craftsmanship
        // IMAGE PROMPT 1: "Vintage woodworking workshop, tools hanging on pegboard, sawdust in afternoon light, worn workbench with current project, warm browns and ambers, documentary style"
        // IMAGE PROMPT 2: "Father teaching child to use hand tools, concentrated expressions, wood shavings, warm workshop lighting, intimate documentary moment"
        FlipPage(type: .text, title: "Dad's Workshop Wisdom", text: """
        The workshop sat behind our house like a treasure chest of mysteries. As a child, I was only allowed to peer through the doorway, watching Dad's hands transform raw wood into furniture, toys, and dreams. The day he finally said, "Come on in, it's time," changed everything.
        
        "Every tool has a purpose," Dad began, his calloused hands running along the worn handle of his grandfather's hammer. "Respect them, and they'll serve you well. Rush them, and someone gets hurt." It was my first lesson, though I didn't know then how it applied to more than just woodworking.
        
        We started with something simple—a birdhouse. "Measure twice, cut once," he'd say, watching as I carefully marked the wood. The first cut was crooked. I wanted to start over, but Dad stopped me. "Nothing in life is perfect. We learn to work with what we have, make it beautiful anyway."
        
        The sawdust had a sweet smell that I can still conjure today. It covered everything in a fine layer, like snow, marking us as makers, creators. Dad would blow it off his workbench at the end of each day, revealing the scratches and stains below. "Every mark tells a story," he'd say. "This burn here? That's from the summer we built your mother's garden bench. This gouge? Your brother's first attempt at carving."
        
        Over months, my hands learned the language of wood—how pine was forgiving, oak stubborn, cherry beautiful but demanding. Dad taught through metaphors I wouldn't understand until years later. "See how the grain runs? Always work with it, never against it. Same with people."
        
        The treehouse project came the summer I turned twelve. It wasn't just about building; it was about dreaming, planning, problem-solving. We spent weeks drawing designs, calculating loads, selecting the perfect tree. "Foundation matters most," Dad emphasized, spending days on the platform that everything else would rest upon. "Get that wrong, and nothing else matters."
        
        We worked every evening after Dad got home from his job at the factory. His tired eyes would light up as we entered the workshop, as if this was what recharged him. Some days we worked in comfortable silence, the only sounds our breathing and the whisper of sandpaper. Other days, he'd share stories of his father, his childhood, his dreams that became our family's reality.
        
        The day we raised the walls was magical. What had been pieces became structure. "This is the moment," Dad said, stepping back to admire our work, "when a project becomes real. Remember this feeling—it's what keeps you going through the hard parts."
        
        I remember the afternoon we hung the rope ladder. I was frustrated; it kept twisting, refusing to hang straight. Dad watched me struggle, then quietly said, "Sometimes the harder you try to control something, the more it resists. Let it find its own balance." The ladder straightened as soon as I stopped fighting it.
        
        The treehouse stood for twenty years, through storms that should have brought it down. Even after the tree died, the structure held, as if Dad's patience and care had given it a strength beyond mere nails and wood. My own children played in it, and I found myself repeating Dad's words: "Build with love, and it lasts."
        
        When Dad passed, I inherited his tools. Each one carries the oil from his hands, the wear patterns of his grip. Using them, I feel him guide my hands still. In teaching my daughter to use his plane, I hear his voice in mine: "Easy does it. Let the tool do the work. There's no prize for rushing."
        
        The workshop remains, a cathedral of sawdust and memory. Every project I complete there adds another layer to our family's story, another ring in the tree of our legacy. Dad was right—we were building more than furniture. We were building character, patience, and love, one careful cut at a time.
        """),
        
        // Workshop photo for Story 2
        FlipPage(type: .rightPhoto, title: "Workshop Legacy", caption: "Where patience was taught through sawdust and love through craftsmanship.", imageName: "workshop"),
        
        // Story 3: The Immigration Story - Courage and new beginnings
        // IMAGE PROMPT 1: "Vintage sepia photograph style, immigrant family at ship's rail seeing Statue of Liberty, period clothing, hopeful expressions, historical documentary style"
        // IMAGE PROMPT 2: "Modest 1920s American home, family on front porch, American flag, garden with both old country and new country plants, golden afternoon light"
        FlipPage(type: .text, title: "The Courage to Begin Again", text: """
        They say courage isn't the absence of fear—it's moving forward despite it. When my great-grandparents boarded the ship in Naples with their three young children, they had twenty American dollars, six words of English between them, and fear so thick you could taste it. They also had something stronger: hope.
        
        "Papa kept the ship ticket in his breast pocket," Grandma would tell us, "right next to his heart, for the entire voyage. He said it wasn't just paper—it was our family's future."
        
        The crossing took sixteen days. Sixteen days in steerage, where the air was thick with the smell of unwashed bodies, sickness, and dreams. Great-grandma would sing the old lullabies to keep the children calm, her voice competing with the groaning of the ship and the crying of a hundred other children. "Every song," she'd later say, "was a bridge between the world we left and the world we were sailing toward."
        
        They glimpsed the Statue of Liberty through morning fog on April 7, 1923. Papa lifted each child to see her, tears streaming down his weathered face. "Look," he said in Italian, "she welcomes us. We are home." But home was still a stranger, speaking in tongues they didn't understand.
        
        Ellis Island was chaos—a babel of languages, medical inspections, chalk marks on coats that could mean acceptance or rejection. The family waited for six hours, the children restless, parents rigid with tension. When finally approved, when that stamp hit their papers, Great-grandma collapsed into Papa's arms. They had crossed more than an ocean; they had crossed into possibility.
        
        New York City swallowed them whole. They found a tenement on Mulberry Street—two rooms for five people, windows that faced a brick wall, stairs that groaned with the weight of dreams deferred. But that first night, as they sat on wooden crates eating bread and cheese bought with their precious dollars, Papa said, "This is not where we end. This is where we begin."
        
        Work came hard and harsh. Papa found a job in construction, leaving before dawn, returning after dark, his hands increasingly gnarled, his back increasingly bent. Great-grandma took in sewing, her fingers flying over fabric by lamplight while the children slept. Every penny saved was a brick in the foundation of their American dream.
        
        The children learned English with stunning speed, becoming translators for their parents, bridges between old and new. "We spoke Italian at home," Grandma remembered, "English at school, and dreams in both languages."
        
        Within five years, they had saved enough to leave Mulberry Street. The house in Queens was tiny—but it had a yard. Papa planted tomatoes and basil alongside roses and petunias. "Both countries," he'd say, "growing together in American soil."
        
        The Depression tested them, as it tested everyone. But they had survived with less, and they knew how to make something from nothing. Great-grandma's garden fed not just their family but neighbors too. Papa's construction skills, learned in the old country, kept their home standing when others were losing theirs. "In the old country," he'd say, "we learned that family and community are the only real wealth."
        
        When World War II came, their eldest son enlisted immediately. "This country gave us everything," he said. "Now I give back." The blue star in their window was a badge of honor, their son's service the ultimate declaration of belonging.
        
        By their twenty-fifth year in America, Papa owned his own construction company. The hands that had arrived with nothing now signed paychecks for other immigrant families. Great-grandma, who had arrived with recipes in her memory, now ran a small restaurant where homesick Italians found comfort in her cucina.
        
        They became citizens in 1935, the proudest day of their lives. Papa framed the naturalization certificate, hanging it in the living room next to a photo of the village they'd left behind. "We are both," he'd say to anyone who asked. "The leaving made us strong, the arriving made us free."
        
        Fifty years after that foggy morning when they first saw Lady Liberty, they stood in the same spot with their grandchildren and great-grandchildren—doctors, teachers, business owners, artists. Papa, now ancient, lifted his newest great-granddaughter to see the statue, just as he had lifted his own children decades before.
        
        "You see her?" he whispered, his English still accented but proud. "She says welcome. She says you belong. She says you are home." The baby gurgled, reaching toward the statue, toward the future, toward all the possibilities that one act of courage had made possible.
        """),
        
        // Immigration photo for Story 3
        FlipPage(type: .mixed, title: "American Dream", caption: "From twenty dollars to twenty grandchildren—the true American story.", imageName: "ellis_island"),
        
        // Story 4: Mom's Garden of Memories - Growth, nurturing, and seasons of life
        // IMAGE PROMPT 1: "Elderly woman in sun hat tending heirloom tomatoes, morning dew, golden sunrise light, gardening tools, peaceful documentary style"
        // IMAGE PROMPT 2: "Three generations planting together in garden, child's small hands in soil, passing down knowledge, warm afternoon light, lifestyle photography"
        FlipPage(type: .text, title: "Mom's Garden of Life", text: """
        Mom's garden was never just about vegetables. It was her classroom, her sanctuary, her autobiography written in soil and seasons. Every plant had a story, every row a lesson, every harvest a celebration of patience rewarded.
        
        "Gardens teach what schools cannot," she'd say, kneeling in the dirt with her worn gloves and faded sun hat. "They teach you to nurture without controlling, to be patient without being passive, to accept loss while maintaining hope."
        
        The garden began modestly—a small patch behind our first apartment, barely six feet square. Mom planted tomatoes in coffee cans and herbs in cottage cheese containers. "You bloom where you're planted," she'd tell us, "even if you're planted in recycled dairy products."
        
        When we moved to the house with the big backyard, Mom's garden exploded into being. She spent that first spring studying the sun patterns, testing the soil, planning with the intensity of a general preparing for battle. But this wasn't war—it was love, expressed in careful rows and tender cultivation.
        
        I was five when she gave me my own small plot. "This is yours," she said solemnly. "What you plant, how you tend it, what you harvest—all yours." I planted everything too close together, watered too much, and cried when half my plants died. Mom knelt beside me in the mud. "Even master gardeners kill plants," she said. "The difference is they learn why."
        
        Each season brought its rituals. Spring was for planning and planting, the whole family gathered around the kitchen table with seed catalogs and graph paper. Mom would tell us about each variety—this tomato from seeds her mother brought from Italy, these beans from a neighbor who'd moved away, that squash from seeds saved for thirty years.
        
        Summer mornings began in the garden. Mom would be out there at dawn, coffee in one hand, hose in the other, talking to her plants like old friends. "Good morning, tomatoes. Looking strong today. Beans, you need to step it up. Zucchini, calm down, you're taking over everything." We thought she was crazy until we started doing it ourselves.
        
        The garden was where difficult conversations happened. Weeding alongside Mom, the repetitive work somehow made it easier to talk about fears, dreams, heartbreaks. "Plants are good listeners," she'd say. "They keep secrets better than anyone." It was while thinning carrots that I told her I was scared of starting high school. While staking tomatoes that she told me about her miscarriages before I was born.
        
        Mom's garden fed more than our family. She had a gift for knowing who needed what. Mrs. Chen next door would find bags of bok choy on her porch. The young couple with the new baby received tomatoes and basil for easy dinners. The widower down the street got weekly bouquets of zinnias "because beauty matters too, especially when you're grieving."
        
        The lessons were constant but never forced. "See how the corn and beans and squash grow together?" she'd point out. "The corn provides structure, the beans add nitrogen to the soil, the squash leaves shade the ground. They're better together. People are like that too."
        
        When Mom got sick, the garden was what she worried about most. From her hospital bed, she'd quiz us: "Did you water the tomatoes? Are you watching for hornworms? The basil needs to be pinched back." We kept it going, the whole neighborhood actually, everyone taking shifts, keeping Mom's garden alive while she fought to stay alive herself.
        
        The day she came home from her final treatment, cancer-free but exhausted, we wheeled her to the garden. It was July, everything in full bloom, heavy with produce. She cried seeing it—not sad tears, but the kind that water hope back to life. "You kept it going," she whispered. "All of you."
        
        Now I have my own garden, and my daughter has her small plot within it. I find myself saying Mom's words: "Be patient. Water deeply but not too often. Sometimes the best thing you can do is nothing. Trust the process." I talk to my plants in the morning, save seeds in carefully labeled envelopes, and always plant more than I need because someone, somewhere, needs fresh tomatoes and hope.
        
        The heirloom seeds Mom gave me are more valuable than any jewelry. Each packet is labeled in her careful handwriting: "Cherokee Purple tomato - 1987 - from Grandma Rose" or "Kentucky Wonder beans - saved every year since 1962." When I plant them, I'm planting history, love, and the promise that some things, tended carefully, last forever.
        """),
        
        // Garden photo for Story 4
        FlipPage(type: .rightPhoto, title: "Seeds of Legacy", caption: "In gardens, as in life, what we plant with love grows forever.", imageName: "garden_generations")
    ]
    
    // Convert MockBookPage to FlipPage
    static func fromMockBookPage(_ mockPage: MockBookPage) -> FlipPage {
        switch mockPage.type {
        case .cover:
            return FlipPage(type: .cover, title: mockPage.content)
        case .text:
            return FlipPage(type: .text, text: mockPage.content)
        case .photo:
            return FlipPage(type: .rightPhoto, title: "Memories of Achievement", caption: mockPage.content, imageName: mockPage.imageName)
        case .mixed:
            return FlipPage(type: .mixed, caption: mockPage.content, imageName: mockPage.imageName)
        case .twoPageSpread:
            // For two-page spreads, we'll create separate left/right pages
            return FlipPage(type: .leftBars, caption: mockPage.content)
        }
    }
}
