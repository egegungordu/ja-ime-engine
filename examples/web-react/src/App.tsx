import { ThemeToggle } from "@/components/ui/theme-toggle";
import { cn } from "@/lib/utils";
import { useJapaneseIME } from "@/hooks/useJapaneseIME";
import { useState, useRef, useEffect } from "react";
import { Input } from "@/components/ui/input";
import { Loader2, Github } from "lucide-react";

function ExampleCard({ title, example }: { title: string; example: string }) {
  return (
    <div className="rounded-lg border bg-card p-2 text-card-foreground text-sm">
      <div className="font-medium text-muted-foreground">{title}</div>
      <code className="text-foreground">{example}</code>
    </div>
  );
}

function Main() {
  const [error, setError] = useState<string>();
  const { isReady, isLoading, handleKeyDown, handleBeforeInput, handleClick } =
    useJapaneseIME({
      onError: (error) => setError(error.message),
    });
  const [value, setValue] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (isReady && inputRef.current) {
      inputRef.current.focus();
    }
  }, [isReady]);

  return (
    <div className="flex flex-col gap-6">
      <div className="prose dark:prose-invert">
        <p>
          A Japanese IME (Input Method Editor) engine focusing on romaji to
          hiragana/full-width character conversion. Based on Google 日本語入力
          behavior.
        </p>
      </div>

      <div className="flex flex-col gap-4">
        <div className="relative">
          <Input
            ref={inputRef}
            type="text"
            placeholder={
              isLoading
                ? "Loading IME..."
                : isReady
                ? "Type here..."
                : "Failed to load IME"
            }
            disabled={!isReady}
            value={value}
            onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
              setValue(e.target.value)
            }
            onKeyDown={handleKeyDown}
            onBeforeInput={handleBeforeInput}
            onClick={handleClick}
            className="w-full text-5xl placeholder:text-5xl md:text-5xl h-full"
          />
          {isLoading && (
            <div className="absolute right-3 top-1/2 -translate-y-1/2">
              <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
            </div>
          )}
        </div>
        {error && <div className="text-sm text-red-500">{error}</div>}
      </div>

      <div className="flex flex-col gap-2">
        <h2 className="text-sm font-medium text-muted-foreground">Examples</h2>
        <div className="grid gap-2 grid-cols-2 sm:grid-cols-3">
          <ExampleCard title="Basic" example="a → あ, ka → か" />
          <ExampleCard title="Small" example="xya → ゃ, li → ぃ" />
          <ExampleCard title="Sokuon" example="tte → って" />
          <ExampleCard title="Full-width" example="k → ｋ, 1 → １" />
          <ExampleCard title="Punctuation" example=". → 。, ? → ？" />
        </div>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <div className={cn("min-h-screen relative")}>
      <div className="container mx-auto py-8 pb-2 px-4 relative">
        <div className="flex flex-col min-h-[calc(100vh-2.5rem)]">
          <div className="w-full max-w-3xl mx-auto flex-1 flex flex-col gap-6">
            <div className="flex items-center justify-between">
              <h1 className="text-3xl font-bold">Jaime</h1>
              <div className="flex items-center gap-2">
                <ThemeToggle />
              </div>
            </div>
            <main className="flex-1">
              <Main />
            </main>
            <footer className="text-xs text-muted-foreground pt-2.5 pb-1 px-2 border-t flex items-center justify-between">
              <a
                href="https://github.com/egegungordu/jaime"
                target="_blank"
                rel="noopener noreferrer"
                className="hover:text-foreground transition-colors inline-flex items-center gap-1"
              >
                <Github className="h-3.5 w-3.5" />
                View on GitHub
              </a>
            </footer>
          </div>
        </div>
      </div>
    </div>
  );
}
