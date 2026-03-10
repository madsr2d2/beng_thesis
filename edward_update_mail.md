Hi Edward,

Time for a project update. :) I have been working on the design and the verification plan in parallel and I still have about a week left of the design phase according to the time plan. 

Regarding the verification plan:
I got the feeling that I was a bit inconsistent in how I was extracting requirements from the relatively extensive ISO standard. I kept missing stuff and misinterpreting paragraphs - a problem that I guess is unavoidable when trying to translate inherently vague English text into precise requirements.

So I decided to take a step back and attempt a more systematic extraction. I wanted to make sure that I had a comprehensive and well-organized set of requirements to work with before I started implementation. My idea was to extract all normative language form the ISO standard and organized these statements according to layer (LLC, MAC, PCS and FCE), transmission side (transmitter, receiver, both) and scope (bus, frame and node). Here bus refers to requirements that apply to the bus as a whole, frame referee to requirements that apply to a specific frame type (CB, CE, FB, FE) and node refers to requirements that apply to a specific node on the bus. Each requirement should also includes the ISO clause reference and a precondition/event/postcondition breakdown where applicable. I think this should map cleanly onto test bench assert statements and help decide in which test bench a given requirement belongs.

I used an LLM agent (Opus 4.6) for the extraction and classification work. I think this is a good fit for AI as this is exactly the kind of repetitive, pattern-heavy text processing where I would likely miss things an become inconsistent over 100+ requirements. I decided to use TOML as the format to store the verification plan source - easy to read and edit using python script. I then build a small custom MCP server tool enabling consistent edits of the verification plan TOML - the goal here was to alleviate inconsistencies, unintended edits by restricting the way the agent could interact with the TOML source.

I then converted the ISO standard PDF to Markdown (using marker-pdf and some custom post edits of the generated markdown file). The goal here was to enable efficient search of the ISO standard content using the standard Bash search tools available to the agent. I then crafted the initial prompt and let the agent loos on the ISO Markdown equipped with the MCP tools enabling consistent edits of the verification plan TOML.

This generated 168 requirements, which I then reviewed manually to catch misinterpretations and refine classifications. The manual review is still ongoing.

In a post-processing run I added and observability dimension to the requirements - how verifiable each postcondition is at the layer's own interface boundary. Three levels: external (directly measurable at the boundary and verifiable form boundary inputs), derived (manifests at the boundary but depends non-trivially on internal states, requires a reference model), and internal (no runtime stimulus/response relationship to verify - either the requirement defines what inputs are legal rather than what outputs result from legal inputs, or it is an architectural fact verifiable by inspection rather than simulation).

I'd be curious to hear what you think of this approach - both the requirement taxonomy and the AI-assisted extraction workflow.

Regarding the design:
In parallel to the verification plan work I have been working on the design. The existing design collapsed the Mac layer, FCE and both RX and TX paths into a single monolithic FSM the design does generally not map cleanly onto the layered structure and semantic primitives described in the ISO document. Rather than trying to squish FD support into this framework, I decided to decompose the design according to the ISO specified layers and the TX/RX paths and build in FD support from the start. I think this architectural decision will make the verification process much easier as the implementation now aligns with the semantics of the ISO document's requirements. As of now, I have the typing system and the TX path design "done" still missing is the RX path and FCE.

I have appended current state of the report design section and the verification plan in html. Looking forward to your feed back. :)
