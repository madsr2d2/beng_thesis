Hi Fredrik,

Following up on the verification plan. I've been working on reducing the requirement set to
a tractable size, again using an LLM for the processing and classification work.

Each requirement is assigned to one of the four ISO layers (LLC, MAC, PCS, FCE), each of
which has a well-defined service interface in the standard. I used those interfaces (§6.4.5,
§7.2, §8.1.3) along with the configurable generics each layer exposes (e.g. the timing
configurations for the PCS) to classify every requirement by observability at its layer
boundary:

- **External** (106): directly assertable at the layer boundary from interface parameters and config generics alone.
- **Derived** (40): manifests at the boundary but depends non-trivially on internal states - needs a reference model.
- **Internal** (22): structural definition or configuration constraint. Many could be verified by just inspecting the associated constants defined in the VHDL source.

The external set is the primary testbench target. Derived is a second phase pending a
reference model. The same interfaces and generics were then used to rewrite all 168
pre/event/post triplets - each postcondition now names a specific interface signal and
parameter, or an explicit timing formula, making them close to executable test specifications.

One tension worth raising: the existing CAN controller collapses MAC, FCE, and both TX and RX
pipelines into a single FSM, so the layer interfaces used as observability anchors don't map cleanly
unto existing interface signals. Retrofitting FD into this monolithic framework may end up harder than designing the extension
to follow the ISO layer structure from the start - that would also make the verification easier I think.

What do you think? I appended the external flagged requirement set.

Mads
