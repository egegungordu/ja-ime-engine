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
}

interface UseJapaneseIMEProps {
  onError?: (error: Error) => void;
}

export function useJapaneseIME({ onError }: UseJapaneseIMEProps = {}) {
  const imeRef = useRef<JapaneseIME | null>(null);
  const onErrorRef = useRef(onError);
  const [isReady, setIsReady] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const lastCursorPositionRef = useRef(0);

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

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLInputElement>) => {
      try {
        if (!imeRef.current) return;
        const input = event.currentTarget;

        switch (event.key) {
          case "Backspace":
            event.preventDefault();
            imeRef.current.deleteBack();
            const deleteBackPos = input.selectionStart! - 1;
            if (deleteBackPos >= 0) {
              input.value =
                input.value.slice(0, deleteBackPos) +
                input.value.slice(deleteBackPos + 1);
              input.selectionStart = input.selectionEnd = deleteBackPos;
            }
            break;
          case "Delete":
            event.preventDefault();
            imeRef.current.deleteForward();
            const deleteForwardPos = input.selectionStart!;
            if (deleteForwardPos < input.value.length) {
              input.value =
                input.value.slice(0, deleteForwardPos) +
                input.value.slice(deleteForwardPos + 1);
              input.selectionStart = input.selectionEnd = deleteForwardPos;
            }
            break;
          case "ArrowLeft":
            event.preventDefault();
            imeRef.current.moveCursorBack(1);
            const newLeftPos = input.selectionStart! - 1;
            if (newLeftPos >= 0) {
              input.selectionStart = input.selectionEnd = newLeftPos;
              lastCursorPositionRef.current = newLeftPos;
            }
            break;
          case "ArrowRight":
            event.preventDefault();
            imeRef.current.moveCursorForward(1);
            const newRightPos = input.selectionStart! + 1;
            if (newRightPos <= input.value.length) {
              input.selectionStart = input.selectionEnd = newRightPos;
              lastCursorPositionRef.current = newRightPos;
            }
            break;
        }
      } catch (error) {
        onErrorRef.current?.(error as Error);
      }
    },
    [] // Remove onError from deps
  );

  const handleBeforeInput = useCallback(
    (event: React.FormEvent<HTMLInputElement> & { data: string }) => {
      try {
        if (!imeRef.current) return;
        if (event.type === "beforeinput") {
          event.preventDefault();
          const input = event.currentTarget;
          const result = imeRef.current.insert(event.data);

          const pos = input.selectionStart!;

          // Handle deletions first
          if (result.deletedCodepoints > 0) {
            const deleteStart = pos - result.deletedCodepoints;
            const deleteEnd = pos;
            input.value =
              input.value.slice(0, deleteStart) + input.value.slice(deleteEnd);
            input.selectionStart = input.selectionEnd = deleteStart;
          }

          // Then insert the new text
          const currentPos = input.selectionStart!;
          input.value =
            input.value.slice(0, currentPos) +
            result.insertedText +
            input.value.slice(currentPos);
          const newPos = currentPos + [...result.insertedText].length;
          input.selectionStart = input.selectionEnd = newPos;
          lastCursorPositionRef.current = newPos;
        }
      } catch (error) {
        onErrorRef.current?.(error as Error);
      }
    },
    [] // Remove onError from deps
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

  return {
    isReady,
    isLoading,
    handleKeyDown,
    handleBeforeInput,
    handleClick,
  };
}
