/* One multiplication C = A x B. The stimulus is what goes into memory (dimensions, addresses, A,
   B, interrupt enable); the response is what the monitor finds in memory at the end (C, the DMA
   status the firmware stored, cycles, writes outside C). C is four-state so an element the DMA
   left unknown shows up as X instead of passing as some number. Matrices are row-major. */
class mm_item extends uvm_sequence_item;
  `uvm_object_utils(mm_item)

  // Sizes the constraints depend on, copied from the configuration before randomize.
  int unsigned data_width = 8;
  // Width of each element of C in memory; the same as data_width unless decision 0002 changes.
  int unsigned c_width = 8;
  int unsigned array_size = 4;
  int unsigned max_dim = 12;
  int unsigned region_bytes = REGION_BYTES;
  bit allow_zero_dim = 1'b0;
  bit [31:0] data_mask = 32'hFF;
  bit [31:0] data_min = 32'h80;
  bit [31:0] data_max = 32'h7F;

  rand int unsigned m;
  rand int unsigned k;
  rand int unsigned n;
  rand bit [31:0] addr_a;
  rand bit [31:0] addr_b;
  rand bit [31:0] addr_c;
  rand bit [31:0] a[];
  rand bit [31:0] b[];
  rand bit irq_en;
  rand bit [31:0] fault;
  // A, B and C each take one of the three 4 KiB regions, at an offset that keeps them inside it.
  rand bit relocate;
  rand int unsigned region_a, region_b, region_c;
  rand int unsigned offset_a, offset_b, offset_c;
  // When non-zero, the DUT is reset this many cycles after CMD is set and the operation aborts.
  rand int unsigned reset_after;

  int unsigned op_id;
  logic [31:0] c[];
  bit [31:0] status;
  longint unsigned start_cycle;
  longint unsigned end_cycle;
  int unsigned op_cycles;
  int unsigned latency_cycles;
  int unsigned oob_writes;
  bit aborted;
  // First operation since the reset was released, as opposed to one right after another.
  bit after_reset;

  constraint c_dims {
    if (allow_zero_dim) {
      m <= max_dim;
      k <= max_dim;
      n <= max_dim;
    } else {
      m inside {[1 : max_dim]};
      k inside {[1 : max_dim]};
      n inside {[1 : max_dim]};
    }
  }

  constraint c_fit {
    m * k * (data_width / 8) <= region_bytes;
    k * n * (data_width / 8) <= region_bytes;
    m * n * (c_width / 8) <= region_bytes;
  }

  /* The default keeps the standard regions; a sequence that wants them moved sets relocate with a
     hard constraint (a dist would lose to this soft one). Offsets are bounded on their own and
     compared with a subtraction, so no 32-bit sum can wrap around. */
  constraint c_addr {
    soft relocate == 1'b0;
    if (!relocate) {
      soft addr_a == REGION_A;
      soft addr_b == REGION_B;
      soft addr_c == REGION_C;
    } else {
      region_a < 3;
      region_b < 3;
      region_c < 3;
      unique {region_a, region_b, region_c};
      offset_a < region_bytes;
      offset_b < region_bytes;
      offset_c < region_bytes;
      offset_a % (data_width / 8) == 0;
      offset_b % (data_width / 8) == 0;
      offset_c % (c_width / 8) == 0;
      offset_a <= region_bytes - m * k * (data_width / 8);
      offset_b <= region_bytes - k * n * (data_width / 8);
      offset_c <= region_bytes - m * n * (c_width / 8);
      addr_a == REGION_A + region_a * region_bytes + offset_a;
      addr_b == REGION_A + region_b * region_bytes + offset_b;
      addr_c == REGION_A + region_c * region_bytes + offset_c;
    }
  }

  constraint c_reset {soft reset_after == 0;}

  constraint c_size {
    a.size() == m * k;
    b.size() == k * n;
  }

  // Extremes are weighted up: they are what makes a partial sum wrap.
  constraint c_data {
    foreach (a[i]) {
      (a[i] & ~data_mask) == 0;
      a[i] dist {0 :/ 1, data_min :/ 1, data_max :/ 1, data_mask :/ 1, [0 : data_mask] :/ 6};
    }
    foreach (b[i]) {
      (b[i] & ~data_mask) == 0;
      b[i] dist {0 :/ 1, data_min :/ 1, data_max :/ 1, data_mask :/ 1, [0 : data_mask] :/ 6};
    }
  }

  constraint c_fault {soft fault == 0;}

  function new(string name = "mm_item");
    super.new(name);
  endfunction

  function void set_sizes(input int unsigned width, input int unsigned mesh,
                          input int unsigned largest, input int unsigned cwidth = 0);
    data_width = width;
    c_width = (cwidth == 0) ? width : cwidth;
    array_size = mesh;
    max_dim = largest;
    data_mask = width_mask(width);
    data_min = 32'h1 << (width - 1);
    data_max = data_min - 1;
  endfunction

  function int unsigned elem_bytes();
    return data_width / 8;
  endfunction

  function int unsigned c_bytes();
    return c_width / 8;
  endfunction

  function bit [31:0] flags();
    return fault | 32'(irq_en);
  endfunction

  function void do_copy(uvm_object rhs);
    mm_item t;
    super.do_copy(rhs);
    if (!$cast(t, rhs)) `uvm_fatal("MM_ITEM", "do_copy: not an mm_item")
    data_width = t.data_width;
    c_width = t.c_width;
    array_size = t.array_size;
    max_dim = t.max_dim;
    region_bytes = t.region_bytes;
    allow_zero_dim = t.allow_zero_dim;
    data_mask = t.data_mask;
    data_min = t.data_min;
    data_max = t.data_max;
    m = t.m;
    k = t.k;
    n = t.n;
    addr_a = t.addr_a;
    addr_b = t.addr_b;
    addr_c = t.addr_c;
    a = t.a;
    b = t.b;
    irq_en = t.irq_en;
    fault = t.fault;
    relocate = t.relocate;
    reset_after = t.reset_after;
    op_id = t.op_id;
    c = t.c;
    status = t.status;
    start_cycle = t.start_cycle;
    end_cycle = t.end_cycle;
    op_cycles = t.op_cycles;
    latency_cycles = t.latency_cycles;
    oob_writes = t.oob_writes;
    aborted = t.aborted;
    after_reset = t.after_reset;
  endfunction

  // Two operations match when they asked for the same thing and the DUT answered the same.
  function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    mm_item t;
    if (!$cast(t, rhs)) return 0;
    if (!super.do_compare(rhs, comparer)) return 0;
    if (m != t.m || k != t.k || n != t.n) return 0;
    if (addr_a != t.addr_a || addr_b != t.addr_b || addr_c != t.addr_c) return 0;
    if (a != t.a || b != t.b || irq_en != t.irq_en || fault != t.fault) return 0;
    if (status != t.status || c.size() != t.c.size()) return 0;
    foreach (c[i]) if ((c[i] & data_mask) !== (t.c[i] & data_mask)) return 0;
    return 1;
  endfunction

  function string convert2string();
    string s;
    s = $sformatf("op %0d: M=%0d K=%0d N=%0d A=0x%08h B=0x%08h C=0x%08h irq_en=%0d", op_id, m, k,
                  n, addr_a, addr_b, addr_c, irq_en);
    if (fault != 0) s = {s, $sformatf(" fault=0x%0h", fault)};
    if (reset_after != 0) s = {s, $sformatf(" reset_after=%0d", reset_after)};
    if (aborted) return {s, " ABORTED"};
    return {s, $sformatf(" status=0x%0h cycles=%0d latency=%0d oob=%0d", status, op_cycles,
                         latency_cycles, oob_writes)};
  endfunction

  function string matrix_string(input string which);
    string s = "";
    int unsigned rows = (which == "B") ? k : m;
    int unsigned cols = (which == "A") ? k : n;
    for (int unsigned i = 0; i < rows; i++) begin
      s = {s, "\n  "};
      for (int unsigned j = 0; j < cols; j++) begin
        logic [31:0] v;
        if (which == "A") v = a[i*cols+j];
        else if (which == "B") v = b[i*cols+j];
        else v = (i * cols + j < c.size()) ? c[i*cols+j] : 'x;
        if ($isunknown(v)) s = {s, $sformatf(" %8s", "x")};
        else s = {s, $sformatf(" %8d", signed_value(v, (which == "C") ? c_width : data_width))};
      end
    end
    return s;
  endfunction

endclass
