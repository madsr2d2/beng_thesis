Hi Fredrik,

Following up on our conversation about `can_node_clock.vhd`. I found 2 ISO non-conformance issues. Bug 1 is probably the most severe, it is triggered on any sync edge in phase_seg_2. Bug 2 only manifests on a glitchy bus. 

---

**Bug 1: Sync_Seg skipped regardless of phase error magnitude in Phase_Seg2**

So the issue is in how the code handles a resync edge that arrives during Phase_Seg2 (negative phase error). ISO 11898-1:2024 Section 7.3.5.4 defines two different outcomes depending on the magnitude of the phase error:

- **|e| <= SJW:** Phase_Seg2 is shortened by |e|. ISO says the effect is the same as hard synchronization, meaning Sync_Seg of the next bit is skipped and the next bit starts directly at Prop_Seg.
- **|e| > SJW:** Phase_Seg2 is shortened by SJW only. In this case Sync_Seg is NOT skipped - the next bit starts normally through Sync_Seg then Prop_Seg.

Looking at the code, it appears that the skip condition fires for any shortening at all - both |e| <= SJW and |e| > SJW. So all sync edges arriving in Phase_Seg2 result in Sync_Seg being skipped, which is not ISO-conformant for the |e| > SJW case.

```vhdl
if time_quantum_count >= v_phase_seg2_length then
  segment            <= s_sync;
  transmit_o         <= '1';
  time_quantum_count <= 0;
  phase_seg2_length  <= gc_default_phase_seg_2_length;
  -- it skips the sync stage, if the second segment was shorten.
  if (v_phase_seg2_length /= (gc_default_phase_seg_2_length - 1)) then
    segment <= s_seg_1;
  end if;
end if;
```

---

**Bug 2: Missing synchronization guards from ISO 7.3.5.1 - no protection against false edges**

ISO 11898-1:2024 Section 7.3.5.1 defines two guards that prevent the node from resyncing on false edges:

- **Rule (a):** Only one synchronization per bit time shall be allowed.
- **Rule (b):** An edge shall only cause synchronization if the previous sample point was recessive.

The module implements neither rule a or b. There is no `sync_inhibit` flag, and the bus value at the sample point is not latched or checked. So on a noisy bus, a glitch producing a brief recessive spike during a dominant bit would trigger a false resync. And if multiple glitches hit within the same bit, each one would trigger its own correction.

---

Best,
Mads
