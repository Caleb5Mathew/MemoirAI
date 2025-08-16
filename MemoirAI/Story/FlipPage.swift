import Foundation

// MARK: - FlipPage Model
struct FlipPage: Codable, Identifiable {
    let id = UUID()
    let type: PageType
    let title: String?
    let caption: String?
    let text: String? // Full text content for text pages
    let imageBase64: String?
    let imageName: String?
    
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

// MARK: - Sample FlipPages with Rich Content
extension FlipPage {
    static let samplePages: [FlipPage] = [
        // Cover page
        FlipPage(type: .cover, title: "Life Stories", caption: "A Collection of Memories"),
        
        // Story 1: The Summer of Discovery (Extended 4x)
        FlipPage(type: .text, title: "The Summer of Discovery", text: """
        It was the summer of 1985 when everything changed. The air was thick with possibility, and the world seemed to stretch endlessly before me. I was sixteen, standing at the threshold between childhood and something else entirely.
        
        That morning, I woke before dawn, the birds just beginning their symphony. The old oak tree outside my window cast dancing shadows on my bedroom wall. I knew this day would be different. My grandfather had promised to teach me something that would "change the way I see the world."
        
        Down in the kitchen, the smell of fresh coffee mixed with bacon filled the air. Grandpa sat at the worn wooden table, his weathered hands wrapped around a steaming mug. He looked up at me with those piercing blue eyes that seemed to hold decades of wisdom.
        
        "Ready, kiddo?" he asked, a slight smile playing at the corners of his mouth. I nodded, though I had no idea what I was ready for.
        
        We walked out to the barn as the sun painted the horizon in shades of gold and crimson. The morning dew still clung to the grass, each blade sparkling like tiny diamonds. Grandpa's stride was purposeful, measured—the walk of someone who knew exactly where they were going and why.
        
        Inside the barn, dust motes danced in the slanted beams of sunlight. The familiar smell of hay and leather enveloped us. But today, Grandpa led me past the usual tools and equipment to a corner I'd never paid attention to before. There, covered by an old canvas tarp, was something that would change my life forever.
        
        "This," he said, pulling away the tarp with a flourish, "belonged to your grandmother." Beneath was an antique camera, its brass fittings gleaming despite years of storage. It was a large format camera, the kind that required patience, precision, and an understanding of light that went beyond mere point and shoot.
        
        "Photography," Grandpa continued, "isn't about capturing what you see. It's about capturing what you feel. Your grandmother understood that. She saw the world differently through that lens, and she taught me to see it too."
        
        Over the next several hours, Grandpa taught me the fundamentals—aperture, shutter speed, composition. But more than that, he taught me to really look at the world around me. To notice how the light changed throughout the day, how shadows could tell stories, how a single moment captured could speak volumes.
        
        We spent the entire summer with that camera. I learned to develop film in the makeshift darkroom Grandpa set up in the basement. The first time I watched an image slowly appear on the paper in the developer tray, it felt like magic. Pure, undeniable magic.
        
        By August, I had filled dozens of rolls of film. Pictures of the farm, of Grandpa, of the changing landscape around us. But more than pictures, I had captured memories, emotions, entire stories within single frames. That camera became an extension of myself, a way to communicate things I couldn't put into words.
        
        Years later, I would become a professional photographer, traveling the world and capturing stories for major publications. But nothing would ever compare to that summer of discovery, when my grandfather gave me not just a camera, but a new way of seeing the world.
        """),
        
        // Using actual farmhouse image from Assets
        FlipPage(type: .rightPhoto, title: "Summer Memories", caption: "The old farmhouse where it all began, unchanged by time.", imageName: "farmhouse"),
        
        // Story 2: First Day at University (Extended 4x)
        FlipPage(type: .text, title: "New Beginnings", text: """
        September arrived with a nervous energy I'd never experienced before. The university campus sprawled before me like a small city, full of Gothic buildings and modern glass structures that somehow coexisted in perfect harmony.
        
        My dormitory room was small but filled with potential. Two beds, two desks, and a window overlooking the quad where students lounged on the grass, tossing frisbees and discussing philosophy. My roommate hadn't arrived yet, so I had these precious moments to myself.
        
        I unpacked slowly, placing each item carefully as if the arrangement would somehow determine my success over the next four years. The photo of my family went on the desk, my grandmother's quilt on the bed, and the lucky penny from my father in my pocket where it would stay throughout my studies.
        
        The first knock on my door came just as I was arranging my books on the shelf. Sarah stood there with a bright smile and two cups of coffee. "Figured you could use one," she said. "I'm across the hall." That simple gesture of kindness would bloom into a friendship that would sustain me through late-night study sessions, heartbreaks, and triumphs.
        
        My first class was Introduction to Philosophy with Professor Chen, a tiny woman whose intellectual presence filled the enormous lecture hall. She began with a question: "Why are you here?" Not why were we in her class, but why were we here, in this universe, at this moment. The question haunted me for weeks.
        
        The campus revealed itself slowly over those first months. The library, with its seemingly endless stacks and hidden study nooks, became my second home. I discovered the coffee shop that stayed open until 2 AM, where students debated everything from quantum physics to the meaning of contemporary art. The old elm trees that lined the main walkway became my confidants during long, contemplative walks.
        
        My roommate, James, arrived three days late with a guitar, a collection of vinyl records, and stories from a gap year spent traveling through South America. Our room became a gathering place for an eclectic group of friends—future doctors, artists, engineers, and dreamers. We'd stay up until dawn discussing our plans to change the world, fueled by cheap pizza and expensive dreams.
        
        The academic challenges pushed me beyond what I thought possible. Dr. Rodriguez's chemistry class nearly broke me until I learned that asking for help wasn't a sign of weakness but of wisdom. The study group I reluctantly joined became my support system, and together we conquered equations that had seemed impossible alone.
        
        Winter came early that year, blanketing the campus in snow. The quad transformed into a winter wonderland, complete with impromptu snowball fights and snow sculptures that would make the local news. I remember standing at my window one December evening, watching the snow fall, feeling for the first time that I truly belonged somewhere.
        
        Spring brought new challenges and opportunities. I changed my major twice, joined the photography club (remembering my grandfather's lessons), and fell in love for the first time. Her name was Elena, and she taught me that the heart could hold both immense joy and profound vulnerability simultaneously.
        
        By the end of that first year, I was no longer the nervous teenager who had arrived in September. The university had begun its work of transformation, though I wouldn't fully understand the magnitude of that change until years later. Those hallowed halls didn't just educate me; they shaped me, challenged me, and ultimately, freed me to become who I was meant to be.
        """),
        
        // IMAGE PROMPT: "Historic university bell tower, Gothic architecture, ivy-covered stone walls, autumn afternoon light, students walking on tree-lined paths below, classic American college campus, architectural photography style, warm golden hour lighting"
        FlipPage(type: .rightPhoto, title: "Campus Life", caption: "The historic bell tower that would mark the hours of my education.", imageName: "university"),
        
        // Story 3: The Unexpected Journey (Extended 4x)
        FlipPage(type: .text, title: "The Road Less Traveled", text: """
        Sometimes life's most profound moments come when we least expect them. It was supposed to be a simple business trip to Seattle, nothing more than three days of meetings and hotel conference rooms. But when my flight was cancelled due to an unexpected storm, everything changed.
        
        Instead of waiting at the airport, I rented a car. "Drive," something inside me whispered. "Just drive." And so I did. The Pacific Northwest unfolded before me in layers of green and gray, mountains rising like ancient guardians from the mist.
        
        I stopped at a small diner somewhere outside Portland. The waitress, Martha, had kind eyes and a story to tell. Over pie and coffee, she shared how she'd left everything behind at forty to start over. "Sometimes," she said, "you have to lose yourself to find yourself."
        
        Those words echoed in my mind as I continued driving. By the time I reached Seattle, I had made a decision that would alter the course of my entire life. The meetings no longer seemed important. What mattered was the journey, not the destination.
        
        I called my boss from a payphone at a rest stop overlooking the Columbia River Gorge. "I need some time," I said. The silence on the other end stretched for what felt like hours. "Take what you need," he finally replied. "The job will be here when you're ready." His understanding surprised me, and I wondered later if he too had once stood at such a crossroads.
        
        The road took me through small towns whose names I'd never heard before. Each had its own story, its own rhythm. In Cascade Locks, I watched the salmon run, marveling at their determination to return home against impossible odds. It seemed like a metaphor for something, though I couldn't quite grasp what.
        
        I found myself in a used bookstore in Hood River, where the owner, an elderly man named Thomas, recommended a collection of poems by Mary Oliver. "She writes about paying attention," he said. "Most of us forget to do that." I bought the book and read it that night in a motel room, her words illuminating truths I'd been afraid to acknowledge.
        
        The Cascade Mountains demanded respect. Driving through them in the rain, visibility near zero, I had to trust the road, trust my instincts, trust that I would emerge on the other side. When I finally did, breaking through the clouds into sunshine, it felt like a revelation.
        
        In a small town called Leavenworth, transformed to look like a Bavarian village, I met a couple who had sold everything to open a small inn. They invited me to dinner, and over homemade schnitzel and local wine, they shared their philosophy: "Life is too short to live someone else's dream."
        
        I stayed there for three days, helping them repair a fence, learning to make bread, listening to stories of other travelers who had passed through. Each person who stopped there seemed to be searching for something, and many found it not in reaching their destination, but in the detour itself.
        
        The Olympic Peninsula called to me next. I drove to the edge of the continent, where the Pacific Ocean crashed against rugged cliffs. Standing there, at the westernmost point of the contiguous United States, I felt simultaneously insignificant and infinite. The ocean didn't care about my quarterly reports or five-year plans. It just was, eternal and indifferent, and somehow that was comforting.
        
        In the Hoh Rainforest, I walked among trees that had stood for centuries. The silence there was profound, broken only by the drip of moisture from leaf to leaf. A park ranger told me that the forest was constantly changing, constantly growing, even when it appeared still. "Nothing in nature is static," she said. "Why do we expect our lives to be?"
        
        By the time I returned to Seattle, two weeks had passed. The meetings had been rescheduled, the deals had moved forward without me. But I had changed. The promotion I'd been chasing no longer seemed important. The life I'd carefully constructed felt like a suit that no longer fit.
        
        Six months later, I quit my job and started my own consulting firm, one that allowed me to work remotely, to travel, to take those unexpected detours that lead to life's most important discoveries. That cancelled flight hadn't been an inconvenience; it had been a gift, pushing me onto a road I never would have chosen, but one that led me exactly where I needed to go.
        """),
        
        // IMAGE PROMPT: "Pacific Northwest highway winding through misty mountains, tall evergreen trees on both sides, dramatic fog, moody atmosphere, empty road disappearing into distance, cinematic landscape photography, natural lighting"
        FlipPage(type: .mixed, title: "Wanderlust", caption: "The open road calls to those brave enough to answer.", imageName: "highway"),
        
        // Story 4: Family Traditions (Extended 4x)
        FlipPage(type: .text, title: "Sunday Dinners", text: """
        Every Sunday without fail, our family gathered around grandmother's dining table. The mahogany surface, polished to a mirror shine, reflected the faces of three generations sharing stories, laughter, and occasionally, tears.
        
        The ritual began at dawn with grandmother in her kitchen, flour dusting her apron, humming old hymns as she kneaded dough for her famous rolls. By noon, the house filled with aromas that could summon family members from miles away.
        
        These dinners were more than meals; they were the threads that wove our family tapestry. Uncle Robert would tell his war stories, each version slightly different than the last. Aunt Margaret would update everyone on the neighborhood gossip, her voice dropping to whispers for the juiciest parts.
        
        As children, we'd sneak tastes from the kitchen, dodging grandmother's wooden spoon but never her knowing smile. These moments, simple as they were, became the foundation of who we would become.
        
        The dining room itself was a museum of family history. The walls held photographs spanning decades—sepia-toned portraits of ancestors we'd never met, black and white snapshots of grandmother's wedding day, colorful Polaroids of family vacations. Each image told a story that would inevitably be retold during dinner.
        
        Grandmother's menu never varied, and we wouldn't have wanted it to. Roast chicken that fell off the bone, mashed potatoes whipped with real cream and butter, green beans from her garden cooked with bacon, and those rolls—oh, those rolls. They were legendary, the recipe passed down from her grandmother, never written down, taught only through watching and doing.
        
        The seating arrangement was as fixed as the menu. Grandfather at the head, even years after he passed—his chair remained empty but his presence felt. Grandmother at the foot, orchestrating the meal like a conductor with her symphony. The middle child always sat to her right, the eldest to her left, and we grandchildren filled in the spaces between, creating an unbroken chain of family.
        
        Conversation flowed in predictable patterns. First, the blessing—always led by the youngest who could speak, their small voice carrying the weight of gratitude for us all. Then the passing of dishes, always clockwise, always with compliments to the cook. The first twenty minutes were devoted to eating and appreciating, punctuated only by requests to pass the salt or butter.
        
        Then came the stories. Uncle Robert's tales from Korea grew more elaborate with each telling. The hill got steeper, the enemy more numerous, his bravery more pronounced. We children would exchange glances, but we never challenged him. These weren't lies; they were mythology in the making, the transformation of history into legend.
        
        Aunt Margaret's neighborhood reports were better than any soap opera. Who was feuding with whom, whose children had achieved what, which houses were for sale and why. She had an uncanny ability to know everything about everyone, delivered with just enough judgment to be entertaining but not enough to be cruel.
        
        My father, the quiet one, would share updates from the hardware store he ran. Which farmers were struggling, who was building additions to their homes, the economic pulse of our small town told through the sale of nails and lumber. His stories were less dramatic but somehow more real, grounding us in the present while the others transported us to the past.
        
        After the main course came dessert—always pie, always at least three kinds. Apple from the tree in the backyard, pecan from nuts gathered by the grandchildren, and something seasonal—rhubarb in spring, peach in summer, pumpkin in fall. The debate over which was best was a ritual unto itself, though everyone knew grandmother's apple pie was the true champion.
        
        As the afternoon wore into evening, the children would be released to play while the adults moved to the living room for coffee and more intimate conversation. This was when the real family business was discussed—health concerns, financial worries, relationship troubles. The solutions offered were rarely practical but always heartfelt.
        
        The goodbye ritual could take an hour. First, the announcement of departure, met with protests and promises to stay "just a few more minutes." Then the gradual migration to the door, conversations continuing, stories half-finished promised to be completed next week. The distribution of leftovers, carefully packaged in containers that would be returned the following Sunday. Hugs, multiple rounds of them, each one seemingly the last until another topic arose that required just a bit more discussion.
        
        These dinners continued for thirty-seven years, ending only when grandmother could no longer cook. We tried to maintain the tradition, rotating houses, but it was never quite the same. The food was still good, the stories still told, but something ineffable was lost—perhaps the certainty that comes from ritual observed in the same sacred space.
        
        Now, years later, I host Sunday dinners for my own family. The table is different, the recipes adapted for modern dietary restrictions, the stories new. But sometimes, when the light hits just right and the laughter reaches a certain pitch, I swear I can smell grandmother's rolls baking and hear Uncle Robert clearing his throat to begin another tale. The thread continues, weaving new patterns from old traditions.
        """),
        
        // IMAGE PROMPT: "Multigenerational family gathered around elegant dining table, warm candlelight, vintage 1950s-60s American home interior, mahogany furniture, china plates, homemade feast, Norman Rockwell style, nostalgic warm lighting"
        FlipPage(type: .rightPhoto, title: "Family Gatherings", caption: "Three generations, one table, countless memories.", imageName: "family_dinner"),
        
        // Story 5: Career Milestone (Extended 4x)
        FlipPage(type: .text, title: "The Promotion", text: """
        Twenty years of dedication led to this moment. The corner office with its panoramic city view wasn't just a room; it was a symbol of every late night, every difficult decision, every sacrifice made along the way.
        
        I stood at the window, watching the city pulse with life below. Each light represented someone with their own dreams, their own struggles. It was humbling and inspiring in equal measure.
        
        My mentor, David, had told me years ago: "Success isn't measured by the height of your climb, but by the number of people you lift up along the way." Now, in this position, I finally understood what he meant.
        
        The journey to this office began in a cubicle on the third floor, barely large enough to turn around in. Fresh out of college with a degree and enormous ambition, I thought I'd be running the place within five years. The reality was far different and far more valuable than my naive expectations.
        
        My first boss, Sandra, was tough but fair. She taught me that excellence wasn't about grand gestures but about consistency in small things. "Show up early, stay late when needed, and always deliver more than expected," she'd say. Under her guidance, I learned to write reports that sang, to present ideas with clarity and conviction, to navigate office politics with grace.
        
        The first major project I led was a disaster. Three months of work crumbled in a single client meeting. I wanted to quit, to hide, to blame everyone but myself. David found me in the parking garage, sitting in my car, paralyzed by failure. "The measure of a professional," he said, "isn't how they handle success, but how they recover from failure." He helped me analyze what went wrong, take responsibility, and create a plan to fix it. Six months later, that same client signed our biggest contract to date.
        
        Promotions came slowly at first, then seemed to accelerate. Team leader, department manager, division head. Each step brought new challenges and new opportunities to fail or flourish. I learned to hire well, to delegate effectively, to trust my team while maintaining accountability. The hardest lesson was learning to fire people with compassion, recognizing that sometimes the kindest thing was to help someone find a better fit elsewhere.
        
        The recession tested everything I thought I knew about business. We had to cut budgets by forty percent without losing our core capabilities. I spent nights studying spreadsheets, looking for inefficiencies, ways to do more with less. We restructured, retrained, and somehow emerged stronger. The team that survived that period became the core of our future success.
        
        Innovation became my passion. I pushed for investments in new technologies when others counseled caution. We failed often, but our successes transformed the company. The mobile app everyone said we didn't need became our primary revenue driver. The AI initiative that seemed like science fiction revolutionized our customer service. Each risk taught me to balance vision with pragmatism.
        
        Building culture became as important as building products. I instituted mentorship programs, remembering how David had saved my career. We created scholarship funds for employees' children, flexible work arrangements for parents, and mental health support that went beyond standard benefits. The company became not just a place to work but a community that cared.
        
        The boardroom battles were the most challenging. Convincing skeptical board members to invest in long-term growth over short-term profits required every skill I'd learned. I had to speak their language while staying true to my vision. There were times I compromised, times I stood firm, and slowly, I earned their respect and, more importantly, their trust.
        
        Personal sacrifices accumulated like interest on a loan. Missed birthdays, postponed vacations, relationships that withered from neglect. My marriage survived but bore scars from years of putting work first. My children grew up seeing me more on video calls than at dinner tables. Success, I learned, always has a price, and the bill comes due in unexpected ways.
        
        The day they offered me the position of CEO, I asked for a week to consider. I spent that time not analyzing compensation packages or strategic plans, but sitting with my family, walking in nature, remembering why I'd started this journey. The ambition of youth had transformed into something else—a desire to leave things better than I found them.
        
        Now, standing in this corner office, I think about the intern who started today, nervous and eager, sitting in a cubicle on the third floor. I remember being that person, and I know my real job isn't to manage from this ivory tower but to go down there, introduce myself, and begin mentoring the next generation.
        
        The view from the top is indeed sweet, but not because of the altitude. It's sweet because from here, I can see how many people I can help climb. David was right—success isn't about the height of your climb but about becoming a ladder for others. This office, with all its prestige and pressure, is simply a platform for lifting others up.
        
        Tomorrow, I'll implement the new leadership development program. Next month, we'll launch the community investment initiative. Next year, who knows? But whatever comes, I'll remember that this corner office is not a destination but a responsibility, not an achievement but an opportunity to achieve for others.
        """),
        
        // IMAGE PROMPT: "Modern corporate corner office with floor-to-ceiling windows, panoramic city skyline view at golden hour, minimalist executive furniture, professional photography, dramatic lighting, success and achievement atmosphere"
        FlipPage(type: .rightPhoto, title: "Achievement", caption: "The view from the top is sweeter when shared.", imageName: "office_view"),
        
        // Story 6: Love Story (Extended 4x)
        FlipPage(type: .text, title: "When We Met", text: """
        It was raining in Paris, which seemed almost too cliché to be real. I had ducked into a small bookshop near the Seine, shaking water from my umbrella, when I saw her. She was reading Neruda in the poetry section, completely absorbed, oblivious to the world around her.
        
        I pretended to browse nearby, stealing glances, trying to find the courage to speak. When she finally looked up, our eyes met, and she smiled. That smile changed everything.
        
        "Terrible weather for tourists," she said in accented English. "Perfect weather for readers," I replied. We spent the next four hours in that bookshop, talking about literature, life, and the strange synchronicity that brings strangers together.
        
        Fifty years later, we still return to that bookshop every anniversary. The owner has changed, the books are different, but the magic remains. Some places hold memories so dear that time cannot touch them.
        
        Her name was Isabelle, and she was in Paris studying art restoration at the Sorbonne. I was there on a writing sabbatical, trying to finish a novel that had been eluding me for two years. She laughed when I told her this. "Paris doesn't help you finish things," she said. "It helps you begin them."
        
        We agreed to meet the next day at a café she knew near the Luxembourg Gardens. I arrived thirty minutes early, nervous as a schoolboy, rehearsing conversation topics in my head. When she walked in, wearing a simple blue dress and that same enchanting smile, all my prepared words evaporated. Instead, we talked as if we'd known each other for years.
        
        She showed me her Paris—not the tourist destinations but the hidden corners where real life happened. The tiny bistro where Hemingway used to write, now run by an elderly couple who served the best onion soup in the city. The covered passages where nineteenth-century ghosts seemed to linger. The bench in the Tuileries where she came to sketch when she needed to think.
        
        Our first kiss was on the Pont des Arts, before it became famous for love locks. The sun was setting, painting the Seine gold, and she was explaining the difference between restoration and renovation when I couldn't help myself anymore. "I'm sorry," I said afterward. "No," she replied, "I was hoping you would."
        
        We had three weeks before I had to return to New York. Three weeks that felt like three years and three seconds simultaneously. We crammed a lifetime into those days—morning coffee and croissants, afternoon wanderings through museums where she taught me to see art through a restorer's eyes, evening walks along the river, nights talking until dawn about everything and nothing.
        
        The day before I left, she gave me a small painting she'd restored—a portrait of a woman reading, damaged and forgotten until Isabelle brought it back to life. "So you don't forget," she said. As if I could. As if anyone could forget Isabelle.
        
        Back in New York, we wrote letters—real letters, not emails. Her handwriting was like her, elegant and surprising. She told me about her work, restoring a fresco in a forgotten church, bringing back colors that hadn't been seen for centuries. I told her about my novel, how meeting her had unlocked something, and words were flowing like never before.
        
        Six months later, I returned to Paris. She met me at the airport, and when I saw her, I knew. I knew that home wasn't a place but a person. That night, in the same bookshop where we'd met, I asked her to marry me. The elderly owner, who'd heard our story, opened a bottle of champagne he'd been saving for forty years.
        
        We married the following spring in that forgotten church she'd been restoring. The frescoes she'd brought back to life seemed to bless our union. Her family from Provence, mine from New York, all crammed into that tiny space, united by joy if not by language.
        
        Our life together was a constant restoration project—not fixing what was broken but revealing the beauty that was always there. We lived between Paris and New York, making homes in both cities. She established herself as one of Europe's premier restoration experts while I finally became the writer I'd always wanted to be, inspired by the woman who saw potential in damaged things.
        
        We raised two children, bilingual and bicultural, equally at home in the Met and the Louvre. Sophie inherited her mother's artistic eye and became a photographer. Pierre, despite our artistic genes, became a mathematician, finding beauty in equations we couldn't understand.
        
        There were challenges—visa issues, career conflicts, the strain of maintaining lives on two continents. The year Isabelle's father was dying, and we spent six months in Provence, nearly broke us financially but strengthened us in every other way. We learned that love wasn't just the passionate beginning but the quiet persistence through difficulty.
        
        Now, in our seventies, we've settled primarily in Paris, in an apartment overlooking the bookshop where we met. Every morning, we have coffee at the same café where we had our first real date. The elderly couple who ran it passed on, but their daughter maintains the tradition, and the onion soup is still the best in Paris.
        
        Isabelle still restores paintings, though she's selective now, choosing only projects that speak to her heart. I still write, stories infused with the wisdom that comes from a life well-lived and well-loved. Our children visit with our grandchildren, filling our apartment with noise and life, then leaving us to our comfortable silence.
        
        Sometimes, young couples come into the bookshop while we're browsing, and I see them stealing glances at each other, building courage. Isabelle and I exchange knowing looks, remembering. Love, we've learned, isn't just the dramatic meeting or the passionate beginning. It's the thousands of ordinary days made extraordinary by sharing them with the right person. It's restoration work—patient, careful, revealing beauty layer by layer, year after year.
        """),
        
        // Using actual paris image from Assets
        FlipPage(type: .rightPhoto, title: "Paris in the Rain", caption: "Where every love story should begin.", imageName: "paris"),
        
        // Story 7: Life Lessons (Extended 4x)
        FlipPage(type: .text, title: "What I've Learned", text: """
        After seven decades on this earth, I've collected wisdom like others collect stamps. Each lesson hard-won, each insight paid for with experience.
        
        I've learned that kindness costs nothing but means everything. That the hardest person to forgive is often yourself. That success without fulfillment is the ultimate failure. That time spent with loved ones is never wasted, and time is the only currency that truly matters.
        
        Most importantly, I've learned that life isn't about waiting for the storm to pass; it's about learning to dance in the rain. Every setback taught resilience, every loss taught appreciation, every ending taught that new beginnings are always possible.
        
        If I could tell my younger self one thing, it would be this: Don't be so afraid of making mistakes. Those mistakes will become your greatest teachers, your most interesting stories, and eventually, your wisdom to share.
        
        The twenties taught me ambition. I burned with desire to prove myself, to make my mark, to show the world I mattered. Every opportunity was seized with both hands, every challenge met with fierce determination. I learned that energy without direction is chaos, but properly channeled, it can move mountains.
        
        The thirties brought perspective. The frantic pace of my twenties gave way to a more measured stride. I learned the difference between urgent and important, between noise and signal. Family became not an obligation but a privilege. Work became not just about achievement but about contribution.
        
        The forties introduced me to loss. Parents aged and passed, friends faced cancer and divorce, children grew independent and distant. I learned that grief is love with nowhere to go, that tears are not weakness but evidence of having loved deeply. This decade taught me that everything is temporary, making each moment more precious.
        
        The fifties brought reinvention. The career I'd built began to feel like a cage, and I learned it's never too late to change direction. I went back to school, started new ventures, failed spectacularly, and succeeded beyond my dreams. This decade proved that the only limits we face are the ones we accept.
        
        The sixties introduced me to legacy. Not in terms of money or monuments, but in the lives touched, the wisdom shared, the love given freely without expectation of return. I learned that we live on not in what we accumulated but in what we contributed, not in what we took but in what we gave.
        
        Now in my seventies, I've learned that aging is not about losing youth but about gaining perspective. Every line on my face tells a story, every ache reminds me of an adventure, every memory is a treasure that can never be stolen or lost. I've learned that the body may weaken, but the spirit can soar until the very end.
        
        I've learned practical things too. That the best investment is in relationships. That maintaining friendships requires effort but pays dividends beyond measure. That saying "I love you" should never be postponed. That apologies should be swift and sincere. That grudges are poison you drink hoping others will suffer.
        
        I've learned that happiness is not a destination but a way of traveling. That comparison is the thief of joy. That gratitude can transform any situation. That helping others is the fastest way to help yourself. That listening is more powerful than speaking. That presence is more valuable than presents.
        
        I've learned about courage—not the absence of fear but action in spite of it. Every important decision I've made was accompanied by doubt. Every significant change began with uncertainty. The courage to be vulnerable, to admit ignorance, to ask for help—these are the truest forms of bravery.
        
        I've learned about love in all its forms. Romantic love that evolves from passion to companionship. Parental love that teaches you to put another's needs before your own. Friendship love that sustains you through decades. Self-love that took the longest to learn but proved the most essential.
        
        I've learned that money is a tool, not a goal. That enough is a feast. That simplicity is the ultimate sophistication. That experiences matter more than possessions. That the best things in life aren't things at all.
        
        I've learned about faith—not necessarily religious, but faith in humanity's capacity for good, faith that darkness is temporary, faith that there's meaning in the chaos. This faith has been tested, shaken, nearly broken, but ultimately has proven unbreakable.
        
        I've learned that humor is medicine. That the ability to laugh at yourself is a superpower. That finding absurdity in difficulty is not denial but survival. That a well-timed joke can heal wounds that sympathy cannot touch.
        
        Finally, I've learned that the questions matter more than the answers. That certainty is often ignorance in disguise. That changing your mind is not weakness but growth. That "I don't know" is the beginning of wisdom. That wonder is not childish but essential.
        
        If I could leave one piece of advice for those who come after, it would be this: Pay attention. Life is happening now, not in some future when everything is perfect. The ordinary moments—morning coffee, evening walks, quiet conversations—these are the sacred spaces where life actually happens.
        
        Every sunset watched, every hand held, every tear shed, every laugh shared—these are the threads from which we weave the tapestry of a life. Make yours colorful, make it bold, make it authentically yours. And remember, it's never too late to add a new thread, to change the pattern, to create something beautiful from whatever materials you have at hand.
        """),
        
        // IMAGE PROMPT: "Elderly person's weathered hands holding old photo album, soft window light, vintage photographs visible, nostalgic atmosphere, intimate portrait photography, warm sepia tones mixed with color"
        FlipPage(type: .rightPhoto, title: "Wisdom Gathered", caption: "Seven decades of lessons learned and love shared.", imageName: "wisdom_hands"),
        
        // Closing page
        FlipPage(type: .text, title: "The Story Continues", text: """
        This is not an ending, but a pause in the narrative. Life continues to unfold, each day writing new chapters, adding new characters, creating new adventures.
        
        Thank you for joining me on this journey through memory and time. May your own story be filled with wonder, love, and the courage to live authentically.
        
        Remember: we are all authors of our own lives. Make yours a story worth telling.
        
        As you close this book and return to your own story, carry with you this truth: every ending is also a beginning. The last page of one chapter is merely the first line of the next. Your story is still being written, and the best chapters may be yet to come.
        
        Go forth with courage, with kindness, with curiosity. Make mistakes magnificently. Love without reservation. Live without regret. And always, always remember that your story matters, that your voice deserves to be heard, that your life is a gift not just to you but to everyone whose path crosses yours.
        
        The story continues...
        """)
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