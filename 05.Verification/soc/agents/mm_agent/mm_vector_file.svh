/* One case of the golden vector files written by 03.Reference/tools/generate_dma_vectors.py:
   a line "name M K N", then the rows of A, of B and of the C the Python model computed, in hex
   masked to DATA_WIDTH bits. The first line of the file is the number of cases. */
class mm_vector extends uvm_object;
  `uvm_object_utils(mm_vector)

  string case_name;
  int unsigned m, k, n;
  bit [31:0] a[], b[], c[];

  function new(string name = "mm_vector");
    super.new(name);
  endfunction

  static function bit read_matrix(input int fd, input int unsigned count, ref bit [31:0] v[]);
    v = new[count];
    foreach (v[i]) if ($fscanf(fd, "%h", v[i]) != 1) return 1'b0;
    return 1'b1;
  endfunction

  // Fatal on a file that cannot be read: a test that silently checks nothing must not pass.
  static function void read_file(input string path, ref mm_vector cases[$]);
    int fd = $fopen(path, "r");
    int count;
    cases.delete();
    if (fd == 0) `uvm_fatal("MM_VECTORS", {"cannot open golden vectors ", path})
    if ($fscanf(fd, "%d", count) != 1) `uvm_fatal("MM_VECTORS", {"no case count in ", path})
    for (int i = 0; i < count; i++) begin
      mm_vector v = new($sformatf("vector%0d", i));
      if ($fscanf(fd, "%s %d %d %d", v.case_name, v.m, v.k, v.n) != 4 ||
          !read_matrix(fd, v.m * v.k, v.a) || !read_matrix(fd, v.k * v.n, v.b) ||
          !read_matrix(fd, v.m * v.n, v.c)) begin
        `uvm_fatal("MM_VECTORS", $sformatf("case %0d of %s is incomplete", i, path))
      end
      cases.push_back(v);
    end
    $fclose(fd);
  endfunction

endclass
