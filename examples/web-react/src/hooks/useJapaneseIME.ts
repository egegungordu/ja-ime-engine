import { useCallback, useEffect, useRef, useState } from "react";

interface WasmExports extends WebAssembly.Exports {
  memory: WebAssembly.Memory;
  init: () => void;
  getInputBufferPointer: () => number;
  insert: (length: number) => void;
  getDeletedCodepoints: () => number;
  getInsertedTextLength: () => number;
  getInsertedTextPointer: () => number;
  deleteBack: () => void;
  deleteForward: () => void;
  moveCursorBack: (n: number) => void;
  moveCursorForward: (n: number) => void;
  getMatchCount: () => number;
  getMatchText: (index: number) => number;
  getMatchTextLength: (index: number) => number;
  applyMatch: () => void;
}

class JapaneseIME {
  private wasmInstance: WebAssembly.Instance | null = null;
  private encoder = new TextEncoder();
  private decoder = new TextDecoder();

  async loadFromUrl(url: string) {
    try {
      const response = await fetch(url);
      const wasmBytes = await response.arrayBuffer();
      const wasmModule = await WebAssembly.instantiate(wasmBytes, {
        debug: {
          consoleLog: (arg: any) => console.log(arg),
        },
      });
      this.wasmInstance = wasmModule.instance;
      (this.wasmInstance.exports as WasmExports).init();
      console.log("WebAssembly module loaded successfully");
      return this.listExports();
    } catch (error) {
      console.error("Failed to load WebAssembly module:", error);
      throw error;
    }
  }

  private listExports() {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    return Object.entries(this.wasmInstance.exports).map(
      ([name, value]) => `${name}: ${value.constructor.name}`
    );
  }

  insert(char: string) {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    const exports = this.wasmInstance.exports as WasmExports;

    // Write to input buffer
    const encodedStr = this.encoder.encode(char);
    const inputBufferOffset = exports.getInputBufferPointer();
    const inputView = new Uint8Array(
      exports.memory.buffer,
      inputBufferOffset,
      encodedStr.length + 1
    );
    inputView.set(encodedStr);

    // Process the input
    exports.insert(encodedStr.length);

    // Get the result
    const deletedCodepoints = exports.getDeletedCodepoints();
    const insertedTextLength = exports.getInsertedTextLength();
    const insertedTextPtr = exports.getInsertedTextPointer();

    // Get the inserted text
    const insertedTextView = new Uint8Array(
      exports.memory.buffer,
      insertedTextPtr,
      insertedTextLength
    );
    const insertedText = this.decoder.decode(insertedTextView);

    return {
      deletedCodepoints,
      insertedText,
    };
  }

  deleteBack() {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    (this.wasmInstance.exports as WasmExports).deleteBack();
  }

  deleteForward() {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    (this.wasmInstance.exports as WasmExports).deleteForward();
  }

  moveCursorBack(n: number) {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    (this.wasmInstance.exports as WasmExports).moveCursorBack(n);
  }

  moveCursorForward(n: number) {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    (this.wasmInstance.exports as WasmExports).moveCursorForward(n);
  }

  getMatches(): string[] {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    const exports = this.wasmInstance.exports as WasmExports;

    const matchCount = exports.getMatchCount();
    const matches: string[] = [];

    for (let i = 0; i < matchCount; i++) {
      const textLength = exports.getMatchTextLength(i);
      const textPtr = exports.getMatchText(i);
      const textView = new Uint8Array(
        exports.memory.buffer,
        textPtr,
        textLength
      );
      matches.push(this.decoder.decode(textView));
    }

    return matches;
  }

  applyMatch() {
    if (!this.wasmInstance) throw new Error("WASM not initialized");
    const exports = this.wasmInstance.exports as WasmExports;
    exports.applyMatch();

    // Get the result
    const deletedCodepoints = exports.getDeletedCodepoints();
    const insertedTextLength = exports.getInsertedTextLength();
    const insertedTextPtr = exports.getInsertedTextPointer();

    // Get the inserted text
    const insertedTextView = new Uint8Array(
      exports.memory.buffer,
      insertedTextPtr,
      insertedTextLength
    );
    const insertedText = this.decoder.decode(insertedTextView);

    return {
      deletedCodepoints,
      insertedText,
    };
  }
}

interface UseJapaneseIMEProps {
  onError?: (error: Error) => void;
}

export function useJapaneseIME({ onError }: UseJapaneseIMEProps) {
  const imeRef = useRef<JapaneseIME | null>(null);
  const onErrorRef = useRef(onError);
  const [isReady, setIsReady] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const lastCursorPositionRef = useRef(0);
  const [matches, setMatches] = useState<string[]>([]);
  const [value, setValue] = useState("");
  const [cursorPosition, setCursorPosition] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  // Update the callback ref when it changes
  useEffect(() => {
    onErrorRef.current = onError;
  }, [onError]);

  useEffect(() => {
    const loadWasm = async () => {
      try {
        setIsLoading(true);
        imeRef.current = new JapaneseIME();
        await imeRef.current.loadFromUrl("/libjaime.wasm");
        setIsReady(true);
      } catch (error) {
        onErrorRef.current?.(error as Error);
        setIsReady(false);
      } finally {
        setIsLoading(false);
      }
    };

    loadWasm();

    return () => {
      imeRef.current = null;
    };
  }, []); // Remove onError from deps

  const updateMatches = useCallback(() => {
    if (!imeRef.current) return;
    setMatches(imeRef.current.getMatches());
  }, []);

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLInputElement>) => {
      try {
        if (!imeRef.current) return;

        if (event.key === "Enter" && matches.length > 0) {
          event.preventDefault();
          const result = imeRef.current.applyMatch();

          // Handle deletions and insertions
          const pos = cursorPosition;
          let newValue = value;
          let newPos = pos;

          if (result.deletedCodepoints > 0) {
            const deleteStart = pos - result.deletedCodepoints;
            const deleteEnd = pos;
            newValue = value.slice(0, deleteStart) + value.slice(deleteEnd);
            newPos = deleteStart;
          }

          newValue =
            newValue.slice(0, newPos) +
            result.insertedText +
            newValue.slice(newPos);
          newPos = newPos + [...result.insertedText].length;

          setValue(newValue);
          setCursorPosition(newPos);
          lastCursorPositionRef.current = newPos;
          setMatches([]);
          return;
        }

        switch (event.key) {
          case "Backspace":
            event.preventDefault();
            imeRef.current.deleteBack();
            const deleteBackPos = cursorPosition - 1;
            if (deleteBackPos >= 0) {
              setValue(
                value.slice(0, deleteBackPos) + value.slice(deleteBackPos + 1)
              );
              setCursorPosition(deleteBackPos);
              lastCursorPositionRef.current = deleteBackPos;
            }
            updateMatches();
            break;
          case "Delete":
            event.preventDefault();
            imeRef.current.deleteForward();
            if (cursorPosition < value.length) {
              setValue(
                value.slice(0, cursorPosition) + value.slice(cursorPosition + 1)
              );
            }
            updateMatches();
            break;
          case "ArrowLeft":
            event.preventDefault();
            imeRef.current.moveCursorBack(1);
            const newLeftPos = cursorPosition - 1;
            if (newLeftPos >= 0) {
              setCursorPosition(newLeftPos);
              lastCursorPositionRef.current = newLeftPos;
            }
            break;
          case "ArrowRight":
            event.preventDefault();
            imeRef.current.moveCursorForward(1);
            const newRightPos = cursorPosition + 1;
            if (newRightPos <= value.length) {
              setCursorPosition(newRightPos);
              lastCursorPositionRef.current = newRightPos;
            }
            break;
        }
      } catch (error) {
        onErrorRef.current?.(error as Error);
      }
    },
    [matches, value, cursorPosition, updateMatches] // Add updateMatches to dependencies
  );

  const handleBeforeInput = useCallback(
    (event: React.FormEvent<HTMLInputElement> & { data: string }) => {
      try {
        if (!imeRef.current) return;
        if (event.type === "beforeinput") {
          event.preventDefault();
          const result = imeRef.current.insert(event.data);

          // Handle deletions and insertions
          const pos = cursorPosition;
          let newValue = value;
          let newPos = pos;

          if (result.deletedCodepoints > 0) {
            const deleteStart = pos - result.deletedCodepoints;
            const deleteEnd = pos;
            newValue = value.slice(0, deleteStart) + value.slice(deleteEnd);
            newPos = deleteStart;
          }

          newValue =
            newValue.slice(0, newPos) +
            result.insertedText +
            newValue.slice(newPos);
          newPos = newPos + [...result.insertedText].length;

          setValue(newValue);
          setCursorPosition(newPos);
          lastCursorPositionRef.current = newPos;

          // Update matches after input
          updateMatches();
        }
      } catch (error) {
        onErrorRef.current?.(error as Error);
      }
    },
    [value, cursorPosition, updateMatches] // Add value and cursorPosition to dependencies
  );

  const handleClick = useCallback(
    (event: React.MouseEvent<HTMLInputElement>) => {
      try {
        if (!imeRef.current) return;
        const input = event.currentTarget;
        const currentPos = input.selectionStart!;
        const diff = currentPos - lastCursorPositionRef.current;

        if (diff > 0) {
          imeRef.current.moveCursorForward(diff);
        } else if (diff < 0) {
          imeRef.current.moveCursorBack(-diff);
        }

        lastCursorPositionRef.current = currentPos;
      } catch (error) {
        onErrorRef.current?.(error as Error);
      }
    },
    [] // Remove onError from deps
  );

  // Update cursor position after value changes
  useEffect(() => {
    if (inputRef.current) {
      inputRef.current.selectionStart = inputRef.current.selectionEnd =
        cursorPosition;
    }
  }, [cursorPosition]);

  return {
    // Input props (to be spread)
    inputProps: {
      ref: inputRef,
      value,
      onChange: (e: React.ChangeEvent<HTMLInputElement>) =>
        setValue(e.target.value),
      onKeyDown: handleKeyDown,
      onBeforeInput: handleBeforeInput,
      onClick: handleClick,
      disabled: !isReady,
    },
    // Other values (not to be spread)
    isReady,
    isLoading,
    matches,
  };
}
