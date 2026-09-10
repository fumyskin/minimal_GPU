# STEPS
- [ ] 1.Assembler and a Python emulator of your own ISA. A week, and it forces the ISA to be real before any VHDL exists.
- [ ] 2. One lane in VHDL, GHDL testbench. Test the fixed-point multiply-add against Python, including the saturation cases specifically.
- [ ] 3. Controller with scalar ops, diffed instruction-by-instruction against the emulator.
- [ ] 4. Full Mandelbrot in simulation, one lane — and here's the checkpoint I'd emphasize: have your testbench write the framebuffer contents out as a PGM or PPM file, then open it. You should be looking at a recognizable Mandelbrot set rendered by your RTL, in simulation, before you have touched the board or written a line of video code. Diff it against a twenty-line numpy reference. This single step catches almost everything.
- [ ] 5. Scale to N lanes with a for … generate.
- [ ] 6. VGA output — solid color, then a test pattern, then real pixels.
- [ ] 7. On-board bring-up. Reserve more time than feels reasonable; it is always the step that surprises people.


https://www.youtube.com/shorts/CvbT0eU6EdE