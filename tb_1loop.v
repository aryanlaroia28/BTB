module tb_1loop;

    // Testbench Parameters
    localparam N = 11; // Number of iterations of loop
    localparam CLK_PERIOD = 10;

    // Testbench Signals
    reg clk, reset, stall, flush;
    reg branch_taken_execute;
    reg [31:0] pc_execute, target_pc_execute;
    wire [31:0] pc_out;
    wire btb_hit;
    wire [31:0] predicted_pc;

    // Instantiate the DUT
    fetch_unit_with_btb dut (
        .clk(clk),
        .reset(reset),
        .stall(stall),
        .flush(flush),
        .branch_taken_execute(branch_taken_execute),
        .pc_execute(pc_execute),
        .target_pc_execute(target_pc_execute),
        .pc_out(pc_out),
        .btb_hit(btb_hit),
        .predicted_pc(predicted_pc)
    );

    // Simulation Variables
    reg [31:0] loop_start_pc = 32'h00000004; // Start of loop
    reg [31:0] loop_end_pc = 32'h00000014;   // End of loop
    reg [31:0] loop_target_pc = 32'h00000004; // Target of branch
    reg [31:0] current_pc;

    integer correct_predictions = 0, total_predictions = 0; // total predictions indicate predictions due to btb hit
    integer total_instructions = 0, total_branch_instructions = 0;

    // Clock Generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Test Sequence
    initial begin

        // Enable VCD Dump
        $dumpfile("tb_1loop.vcd"); 
        $dumpvars(0, tb_1loop);  

        // Initialize Signals
        clk = 0; reset = 1; stall = 0; flush = 0;
        branch_taken_execute = 0; pc_execute = 0; target_pc_execute = 0;

        // Deassert Reset
        #(CLK_PERIOD) reset = 0;

        // Simulate Instruction Execution
        current_pc = 32'b0;

        while (current_pc != loop_end_pc + 4) begin
            // Fetch Stage
            if (!stall) begin
                total_instructions = total_instructions + 1;

                // Simulate Branch Instruction
                if (current_pc == loop_end_pc) begin
                    total_branch_instructions = total_branch_instructions + 1;

                    // Condition for loop branch: loop back until exit condition
                    branch_taken_execute = (total_branch_instructions <= N);
                    pc_execute = current_pc;
                    target_pc_execute = branch_taken_execute ? loop_target_pc : loop_end_pc + 4;

                    // Check BTB prediction
                    if (btb_hit) begin
                        if ((branch_taken_execute && predicted_pc == target_pc_execute) ||
                            (!branch_taken_execute && predicted_pc == pc_execute + 4)) begin
                            correct_predictions = correct_predictions + 1;
                        end
                    end

                    flush = 1; // Flushing everytime so that in case there was wrong prediction our pc gets updated properly and ahead results are analysed properly
                    #(CLK_PERIOD);
                    flush = 0;

                    current_pc = branch_taken_execute ? target_pc_execute : loop_end_pc + 4;
                end else begin
                    branch_taken_execute = 0;
                    current_pc = current_pc + 4; // Sequential execution
                end
            end

            // Update BTB (happens internally in the DUT)
            #(CLK_PERIOD);
            if (btb_hit) begin
                // If there was  a btb hit that means we are predicting pc referring to btb table
                total_predictions = total_predictions + 1;
            end

            // Continuous Monitoring after each instruction execution
            $display("Total Instructions: %0d | Current PC: %0h | Branch Taken: %b | BTB Hit: %b | Predicted PC: %0h | Correct Predictions: %0d | Total Predictions: %0d",
                     total_instructions, current_pc, branch_taken_execute, btb_hit, predicted_pc, correct_predictions, total_predictions);

        end


        // Display Results
        $display("Simulation Results:");
        $display("-------------------");
        $display("Total Instructions        : %0d", total_instructions);
        $display("Total Branch Instructions : %0d", total_branch_instructions);
        $display("Total Predictions         : %0d", total_predictions);
        $display("Correct Predictions       : %0d", correct_predictions);
        $display("Prediction Accuracy       : %0.2f%%",
                 (total_predictions > 0) ? (correct_predictions * 100.0 / total_branch_instructions) : 0.0);
        $display("BTB Hit Rate              : %0.2f%%",
                 (total_predictions > 0) ? (total_predictions * 100.0 / total_branch_instructions) : 0.0);

        // End Simulation
        $stop;
    end

endmodule
