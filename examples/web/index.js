class JapaneseIME {
  constructor() {
    this.wasmInstance = null;
    this.encoder = new TextEncoder();
    this.decoder = new TextDecoder();
  }

  async loadFromFile(file) {
    try {
      const wasmBytes = await file.arrayBuffer();
      const wasmModule = await WebAssembly.instantiate(wasmBytes, {
        debug: {
          consoleLog: (arg) => console.log(arg),
        },
      });
      this.wasmInstance = wasmModule.instance;
      this.wasmInstance.exports.init();
      console.log("WebAssembly module loaded successfully");
      return this.listExports();
    } catch (error) {
      console.error("Failed to load WebAssembly module:", error);
      throw error;
    }
  }

  listExports() {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    return Object.entries(this.wasmInstance.exports).map(
      ([name, value]) => `${name}: ${value.constructor.name}`
    );
  }

  insert(char) {
    if (!this.wasmInstance) throw new Error("WASM not initialized");

    // Write to input buffer
    const encodedStr = this.encoder.encode(char);
    const inputBufferOffset = this.wasmInstance.exports.getInputBufferPointer();
    const inputView = new Uint8Array(
      this.wasmInstance.exports.memory.buffer,
      inputBufferOffset,
      encodedStr.length + 1
    );
    inputView.set(encodedStr);

    // Process the input
    this.wasmInstance.exports.insert(encodedStr.length);

    // Get the result
    const deletedCodepoints = this.wasmInstance.exports.getDeletedCodepoints();
    const deletionDirection = this.wasmInstance.exports.getDeletionDirection();
    const insertedTextLength =
      this.wasmInstance.exports.getInsertedTextLength();
    const insertedTextPtr = this.wasmInstance.exports.getInsertedTextPointer();

    // Get the inserted text
    const insertedTextView = new Uint8Array(
      this.wasmInstance.exports.memory.buffer,
      insertedTextPtr,
      insertedTextLength
    );
    const insertedText = this.decoder.decode(insertedTextView);

    return {
      deletedCodepoints,
      deletionDirection:
        deletionDirection === 0
          ? null
          : deletionDirection === 1
          ? "forward"
          : "backward",
      insertedText,
    };
  }

  deleteBack() {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    this.wasmInstance.exports.deleteBack();
  }

  deleteForward() {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    this.wasmInstance.exports.deleteForward();
  }

  moveCursorBack(n) {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    this.wasmInstance.exports.moveCursorBack(n);
  }

  moveCursorForward(n) {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    this.wasmInstance.exports.moveCursorForward(n);
  }
}

class InputFieldManager {
  constructor(inputElement, outputElement) {
    this.input = inputElement;
    this.output = outputElement;
    this.ime = new JapaneseIME();
    this.lastCursorPosition = 0;
  }

  async loadWasm(file) {
    try {
      const exports = await this.ime.loadFromFile(file);
      this.output.textContent = "WASM exports:\n" + exports.join("\n");
      this.input.disabled = false;
    } catch (error) {
      this.output.textContent = "Error loading WASM module: " + error.message;
    }
  }

  handleKeyDown(event) {
    try {
      switch (event.key) {
        case "Backspace":
          event.preventDefault();
          this.ime.deleteBack();
          this.deleteCharacter(-1);
          break;
        case "Delete":
          event.preventDefault();
          this.ime.deleteForward();
          this.deleteCharacter(0);
          break;
        case "ArrowLeft":
          event.preventDefault();
          this.ime.moveCursorBack(1);
          this.moveCursor(-1);
          break;
        case "ArrowRight":
          event.preventDefault();
          this.ime.moveCursorForward(1);
          this.moveCursor(1);
          break;
      }
    } catch (error) {
      console.error("Error handling special key:", error);
      this.output.textContent = "Error: " + error.message;
    }
  }

  handleInput(event) {
    if (event.inputType === "insertText") {
      event.preventDefault();
      try {
        const result = this.ime.insert(event.data);
        this.applyInputResult(result);
        // Update output for debugging
        this.output.textContent = JSON.stringify(result, null, 2);
      } catch (error) {
        console.error("Error handling input:", error);
        this.output.textContent = "Error: " + error.message;
      }
    }
  }

  deleteCharacter(offset) {
    const pos = this.input.selectionStart;
    const deletePos = pos + offset;
    if (deletePos >= 0 && deletePos < this.input.value.length) {
      this.input.value =
        this.input.value.slice(0, deletePos) +
        this.input.value.slice(deletePos + 1);
      this.input.selectionStart = this.input.selectionEnd = deletePos;
    }
  }

  moveCursor(offset) {
    const newPos = this.input.selectionStart + offset;
    if (newPos >= 0 && newPos <= this.input.value.length) {
      this.input.selectionStart = this.input.selectionEnd = newPos;
      this.lastCursorPosition = newPos;
    }
  }

  handleClick(event) {
    const currentPos = this.input.selectionStart;
    const diff = currentPos - this.lastCursorPosition;

    // Move IME cursor based on the difference
    if (diff > 0) {
      this.ime.moveCursorForward(diff);
    } else if (diff < 0) {
      this.ime.moveCursorBack(-diff);
    }

    this.lastCursorPosition = currentPos;
  }

  applyInputResult(result) {
    const pos = this.input.selectionStart;

    // Handle deletions first
    if (result.deletedCodepoints > 0) {
      const deleteStart =
        result.deletionDirection === "backward"
          ? pos - result.deletedCodepoints
          : pos;
      const deleteEnd =
        result.deletionDirection === "backward"
          ? pos
          : pos + result.deletedCodepoints;
      this.input.value =
        this.input.value.slice(0, deleteStart) +
        this.input.value.slice(deleteEnd);
      this.input.selectionStart = this.input.selectionEnd = deleteStart;
    }

    // Then insert the new text
    const currentPos = this.input.selectionStart;
    this.input.value =
      this.input.value.slice(0, currentPos) +
      result.insertedText +
      this.input.value.slice(currentPos);
    const newPos = currentPos + [...result.insertedText].length;
    this.input.selectionStart = this.input.selectionEnd = newPos;
    this.lastCursorPosition = newPos;
  }
}

// Initialize UI handlers
const input = document.getElementById("input");
const output = document.getElementById("output");
const wasmFile = document.getElementById("wasmFile");

// Create input field manager
const inputManager = new InputFieldManager(input, output);

// Disable input until WASM is loaded
input.disabled = true;

// File input handler
wasmFile.addEventListener("change", async (event) => {
  const file = event.target.files[0];
  if (file) {
    await inputManager.loadWasm(file);
  }
});

// Key event handlers
input.addEventListener("keydown", (event) => {
  inputManager.handleKeyDown(event);
});

input.addEventListener("beforeinput", (event) => {
  inputManager.handleInput(event);
});

// Add click event handler
input.addEventListener("click", (event) => {
  inputManager.handleClick(event);
});
