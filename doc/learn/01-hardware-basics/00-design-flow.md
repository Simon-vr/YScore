---
permalink: /learn/01-hardware-basics/00-design-flow/
lang: en
---
# 00. Hardware Design Flow: Waveform, Then Architecture, Then Code

> This is the **standard flow before writing every piece of hardware** in this project. The order is:
> **① draw the intended waveform of the key signals in drawio → ② draw the architecture diagram (make the nets explicit) → ③ then write Verilog**.
>
> Purpose: think through "what value each signal has each cycle" before writing code, then check directly against the waveform after writing,
> to avoid "missing a cycle" and "messy nets", the two most hidden and hardest-to-find kinds of hardware bug.

---

Two typical sources of hardware bugs:

1. **Missing a cycle**: in a multi-cycle pipeline, a signal is latched a cycle too early or too late. Off by one edge on the waveform
   and the whole function is wrong, yet it is hard to spot just by reading code (the counterintuitive "value takes effect after the edge" of sequential logic).
2. **Messy nets**: module interface names, widths, and connection relationships are a muddle in your head, causing misconnections at instantiation.

**Drawing forces you to think the timing and interfaces through first**:

- Drawing the waveform = fixing the advance of each stage's token and "when each signal is valid / when it is latched".
- Drawing the architecture = listing each module's input/output nets, widths, and sources/destinations clearly.

Writing code is just "translating" the diagrams into Verilog, which greatly reduces the chance of error.
