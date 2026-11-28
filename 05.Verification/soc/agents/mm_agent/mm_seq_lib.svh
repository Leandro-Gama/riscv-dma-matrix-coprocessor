/* Sequences. Each builds its items with start_item / randomize / finish_item, sized to the DUT
   from the configuration the sequencer carries. A directed sequence fixes what it is about with
   inline constraints and, when the values follow a pattern, fills A and B right after randomize. */
class mm_base_seq extends uvm_sequence #(mm_item);
  `uvm_object_utils(mm_base_seq)
  `uvm_declare_p_sequencer(mm_sequencer)

  int unsigned num_ops = 1;

  function new(string name = "mm_base_seq");
    super.new(name);
  endfunction

  function mm_item new_item(input string name);
    mm_item it = mm_item::type_id::create(name);
    it.set_sizes(p_sequencer.cfg.data_width, p_sequencer.cfg.array_size,
                 p_sequencer.cfg.max_dim, p_sequencer.cfg.c_width);
    return it;
  endfunction

  function int unsigned mesh();
    return p_sequencer.cfg.array_size;
  endfunction

  // A directed operation may be larger than the random ones are allowed to be.
  function void allow(mm_item it, input int unsigned dm, input int unsigned dk,
                      input int unsigned dn);
    int unsigned largest = (dm > dk) ? dm : dk;
    if (dn > largest) largest = dn;
    if (largest > it.max_dim) it.max_dim = largest;
  endfunction

  // One operation of fixed dimensions with random data.
  task send_dims(input string name, input int unsigned dm, input int unsigned dk,
                 input int unsigned dn, input bit irq = 1'b1);
    mm_item it = new_item(name);
    allow(it, dm, dk, dn);
    start_item(it);
    if (!it.randomize() with {
          m == dm;
          k == dk;
          n == dn;
          irq_en == irq;
        }) begin
      `uvm_fatal("MM_SEQ", $sformatf("%s: %0dx%0dx%0d did not randomize", name, dm, dk, dn))
    end
    finish_item(it);
  endtask

endclass

// One operation the size of the mesh, with small known values.
class mm_smoke_seq extends mm_base_seq;
  `uvm_object_utils(mm_smoke_seq)

  function new(string name = "mm_smoke_seq");
    super.new(name);
  endfunction

  task body();
    mm_item it = new_item("smoke");
    int unsigned s = mesh();
    start_item(it);
    if (!it.randomize() with {
          m == s;
          k == s;
          n == s;
          irq_en == 1'b1;
          foreach (a[i]) a[i] == ((i % 7) + 1);
          foreach (b[i]) b[i] == (((i % 5) + 32'hFFFF_FFFE) & data_mask);
        }) begin
      `uvm_fatal("MM_SEQ", "smoke item did not randomize")
    end
    finish_item(it);
  endtask

endclass

// num_ops operations with everything random; about a third of them move A, B and C around.
class mm_rand_seq extends mm_base_seq;
  `uvm_object_utils(mm_rand_seq)

  function new(string name = "mm_rand_seq");
    super.new(name);
  endfunction

  task body();
    for (int unsigned i = 0; i < num_ops; i++) begin
      mm_item it = new_item($sformatf("rand%0d", i));
      // Drawn here and imposed as a hard constraint: a dist would lose to the soft default.
      bit move = ($urandom_range(2) == 0);
      start_item(it);
      if (!it.randomize() with {relocate == move;}) begin
        `uvm_fatal("MM_SEQ", "random item did not randomize")
      end
      finish_item(it);
    end
  endtask

endclass

// The cases of the golden vector file for this mesh and width, through the DUT.
class mm_vectors_seq extends mm_base_seq;
  `uvm_object_utils(mm_vectors_seq)

  function new(string name = "mm_vectors_seq");
    super.new(name);
  endfunction

  task body();
    mm_vector cases[$];
    mm_vector::read_file(p_sequencer.cfg.vectors_file, cases);
    foreach (cases[i]) begin
      mm_item it = new_item(cases[i].case_name);
      allow(it, cases[i].m, cases[i].k, cases[i].n);
      start_item(it);
      if (!it.randomize() with {
            m == cases[i].m;
            k == cases[i].k;
            n == cases[i].n;
          }) begin
        `uvm_fatal("MM_SEQ", {"vector case ", cases[i].case_name, " did not randomize"})
      end
      it.a = cases[i].a;
      it.b = cases[i].b;
      `uvm_info("MM_SEQ", $sformatf("golden case %s: %0dx%0dx%0d", cases[i].case_name,
                                    cases[i].m, cases[i].k, cases[i].n), UVM_LOW)
      finish_item(it);
    end
  endtask

endclass

/* Every combination of the four classes of M, K and N against the mesh (smaller, equal, multiple,
   larger with remainder): the 64 cases of the main coverage cross, in random order. */
class mm_tiling_seq extends mm_base_seq;
  `uvm_object_utils(mm_tiling_seq)

  function new(string name = "mm_tiling_seq");
    super.new(name);
  endfunction

  function int unsigned pick(input int unsigned cls, input int unsigned s);
    int unsigned v;
    unique case (cls)
      0: return (s > 1) ? $urandom_range(s - 1, 1) : 1;
      1: return s;
      2: return s * $urandom_range(3, 2);
      default: begin
        do v = $urandom_range(3 * s - 1, s + 1); while (v % s == 0);
        return v;
      end
    endcase
  endfunction

  task body();
    int unsigned combos[$];
    int unsigned s = mesh();
    for (int unsigned c = 0; c < 64; c++) combos.push_back(c);
    combos.shuffle();
    foreach (combos[i]) begin
      int unsigned c = combos[i];
      send_dims($sformatf("tiling%0d", c), pick(c / 16, s), pick((c / 4) % 4, s), pick(c % 4, s),
                1'(i % 2));
    end
  endtask

endclass

// Extreme operands: the values that make partial sums wrap, zeros and an identity.
class mm_limits_seq extends mm_base_seq;
  `uvm_object_utils(mm_limits_seq)

  function new(string name = "mm_limits_seq");
    super.new(name);
  endfunction

  task send_pattern(input string name, input int unsigned dm, input int unsigned dk,
                    input int unsigned dn, input int pa, input int pb);
    mm_item it = new_item(name);
    allow(it, dm, dk, dn);
    start_item(it);
    if (!it.randomize() with {
          m == dm;
          k == dk;
          n == dn;
        }) begin
      `uvm_fatal("MM_SEQ", {name, " did not randomize"})
    end
    if (pa != 0) begin
      for (int unsigned i = 0; i < dm; i++)
      for (int unsigned j = 0; j < dk; j++) it.a[i*dk+j] = value(pa, it, i, j);
    end
    if (pb != 0) begin
      for (int unsigned i = 0; i < dk; i++)
      for (int unsigned j = 0; j < dn; j++) it.b[i*dn+j] = value(pb, it, i, j);
    end
    finish_item(it);
  endtask

  // Patterns: 0 keeps the random data, 1 minimum, 2 maximum, 3 zero, 4 minus one, 5 identity,
  // 6 max/min alternating, 7 min/max every third, 8 small values (-1, 0, 1) that never wrap.
  function bit [31:0] value(input int pattern, input mm_item it, input int unsigned i,
                            input int unsigned j);
    unique case (pattern)
      1: return it.data_min;
      2: return it.data_max;
      3: return 32'h0;
      4: return it.data_mask;
      5: return (i == j) ? 32'h1 : 32'h0;
      6: return ((i + j) % 2) ? it.data_max : it.data_min;
      7: return ((i + j) % 3) ? it.data_min : it.data_max;
      8: return (32'((i + 2 * j) % 3) - 32'h1) & it.data_mask;
      default: return 32'h0;
    endcase
  endfunction

  task body();
    int unsigned s = mesh();
    send_pattern("min_x_min", s, 2 * s, s, 1, 1);
    send_pattern("max_x_min", s, 2 * s, s, 2, 1);
    send_pattern("max_x_max", s + 1, 3 * s, s, 2, 2);
    send_pattern("zero_a", s, s, s, 3, 0);
    send_pattern("zero_b", s, s + 1, s, 0, 3);
    send_pattern("identity_b", s + 1, s, s, 0, 5);
    send_pattern("minus_one", s, 2 * s + 1, s, 4, 4);
    send_pattern("alternating", s + 1, 2 * s, s + 1, 6, 7);
    send_pattern("small_k_sub", s, (s > 1) ? s - 1 : 1, s, 8, 8);
    send_pattern("small_k_multi", s, 2 * s, s, 8, 8);
  endtask

endclass

// Operations back to back without reset, each different from the one before.
class mm_b2b_seq extends mm_base_seq;
  `uvm_object_utils(mm_b2b_seq)

  function new(string name = "mm_b2b_seq");
    super.new(name);
    num_ops = 8;
  endfunction

  task body();
    int unsigned s = mesh();
    for (int unsigned i = 0; i < num_ops; i++) begin
      mm_item it = new_item($sformatf("b2b%0d", i));
      start_item(it);
      if (!it.randomize() with {
            m inside {[1 : 2 * s + 1]};
            k inside {[1 : 2 * s + 1]};
            n inside {[1 : 2 * s + 1]};
            irq_en == 1'(i % 2);
            relocate == 1'((i / 2) % 2);
          }) begin
        `uvm_fatal("MM_SEQ", "back-to-back item did not randomize")
      end
      finish_item(it);
    end
  endtask

endclass

// End by interrupt and end by polling alone, alternated, with the same sizes.
class mm_irq_poll_seq extends mm_base_seq;
  `uvm_object_utils(mm_irq_poll_seq)

  function new(string name = "mm_irq_poll_seq");
    super.new(name);
  endfunction

  task body();
    int unsigned s = mesh();
    for (int unsigned i = 0; i < 6; i++) begin
      send_dims($sformatf("irq%0d", i), s + i / 2, s, s + 1, 1'(i % 2 == 0));
    end
  endtask

endclass

/* Operations the DMA must refuse with ERROR: a zero dimension, C past the end of the memory,
   C and A at addresses nobody answers. Each is followed by a good operation, which must work. */
class mm_error_seq extends mm_base_seq;
  `uvm_object_utils(mm_error_seq)

  function new(string name = "mm_error_seq");
    super.new(name);
  endfunction

  task send_bad(input string name, input int unsigned dm, input int unsigned dk,
                input int unsigned dn, input bit [31:0] a_at, input bit [31:0] c_at);
    mm_item it = new_item(name);
    it.allow_zero_dim = 1'b1;
    allow(it, dm, dk, dn);
    start_item(it);
    if (!it.randomize() with {
          m == dm;
          k == dk;
          n == dn;
          addr_a == a_at;
          addr_c == c_at;
        }) begin
      `uvm_fatal("MM_SEQ", {name, " did not randomize"})
    end
    finish_item(it);
  endtask

  task body();
    int unsigned s = mesh();
    bit [31:0] mem_end = DMEM_BASE + p_sequencer.cfg.dmem_bytes;
    send_bad("dim_m_zero", 0, s, s, REGION_A, REGION_C);
    send_dims("after_m_zero", s, s, s);
    send_bad("dim_k_zero", s, 0, s, REGION_A, REGION_C);
    send_dims("after_k_zero", s, s, s);
    send_bad("dim_n_zero", s, s, 0, REGION_A, REGION_C);
    send_dims("after_n_zero", s, s, s);
    send_bad("c_past_end", 2 * s, s, 2 * s, REGION_A, mem_end - 32'd8);
    send_dims("after_c_past_end", s, s, s);
    send_bad("c_unmapped", s, s, s, REGION_A, 32'h3000_0000);
    send_dims("after_c_unmapped", s, s, s);
    send_bad("a_unmapped", s, s, s, 32'h5000_0000, REGION_C);
    send_dims("after_a_unmapped", s, s, s);
  endtask

endclass

// Resets while an operation runs: early (the firmware is still programming) and in the middle.
class mm_reset_seq extends mm_base_seq;
  `uvm_object_utils(mm_reset_seq)

  function new(string name = "mm_reset_seq");
    super.new(name);
  endfunction

  task send_reset(input string name, input int unsigned dm, input int unsigned after);
    mm_item it = new_item(name);
    allow(it, dm, dm, dm);
    start_item(it);
    if (!it.randomize() with {
          m == dm;
          k == dm;
          n == dm;
          reset_after == after;
        }) begin
      `uvm_fatal("MM_SEQ", {name, " did not randomize"})
    end
    finish_item(it);
  endtask

  task body();
    int unsigned s = mesh();
    send_dims("before", s, s, s);
    send_reset("reset_early", 2 * s, 12);
    send_dims("after_early", s, s + 1, s);
    send_reset("reset_middle", 2 * s, $urandom_range(400, 150));
    send_dims("after_middle", 2 * s, s, s + 1);
  endtask

endclass

// The sizes of the cycle table of the DMA documentation, to compare the meshes.
class mm_latency_seq extends mm_base_seq;
  `uvm_object_utils(mm_latency_seq)

  function new(string name = "mm_latency_seq");
    super.new(name);
  endfunction

  task body();
    int unsigned s = mesh();
    send_dims("lat_tile", s, s, s);
    send_dims("lat_k3", s, 3 * s, s);
    send_dims("lat_wide", 2 * s + 1, s, 2 * s + 3);
    send_dims("lat_cube8", 8, 8, 8);
    send_dims("lat_tile_poll", s, s, s, 1'b0);
  endtask

endclass
