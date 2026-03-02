Hi Fredrik,

Here's the current state of the verification plan — 168 requirements extracted from ISO 11898-1:2024, covering Classic and FD frames (CB, CE, FB, FE).

The initial extraction was done using an LLM. I fed it the standard text and had it identify normative "shall"/"should" statements, classify each one by scope (frame, node, bus), and output them in a structured format. I think this is a good fit for AI - it's the kind of repetitive, pattern-heavy text processing where I would likely miss things or lose consistency over 100+ requirements. I then reviewed everything manually to catch misinterpretations and refine the classifications.

Each requirement is organized by layer (LLC, MAC, PCS, FCE), transmission side (transmitter, receiver, both) and includes the ISO clause reference and a precondition/event/postcondition breakdown where applicable. I think the pre/event/post structure should map cleanly onto testbench assertions.

I'd be curious to hear what you think of this approach - both the taxonomy and the AI-assisted extraction workflow.

Mads
