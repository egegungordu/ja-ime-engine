import { useJapaneseIME } from "@/hooks/useJapaneseIME";
import { useState, useEffect } from "react";
import { Input } from "@/components/ui/input";
import { Loader2 } from "lucide-react";

function ExampleCard({ title, example }: { title: string; example: string }) {
  return (
    <div className="rounded-lg border bg-card p-2 text-card-foreground text-sm">
      <div className="font-medium text-muted-foreground">{title}</div>
      <code className="text-foreground">{example}</code>
    </div>
  );
}

export default function Home() {
  const [error, setError] = useState<string>();
  const { inputProps, isReady, isLoading, matches } = useJapaneseIME({
    onError: (error) => setError(error.message),
  });

  useEffect(() => {
    if (isReady && inputProps.ref.current) {
      inputProps.ref.current.focus();
    }
  }, [isReady, inputProps.ref]);

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
            {...inputProps}
            type="text"
            placeholder={
              isLoading
                ? "Loading IME..."
                : isReady
                ? "Type here..."
                : "Failed to load IME"
            }
            className="w-full text-5xl placeholder:text-5xl md:text-5xl h-full"
          />
          {isLoading && (
            <div className="absolute right-3 top-1/2 -translate-y-1/2">
              <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
            </div>
          )}
        </div>
        {matches.length > 0 && (
          <>
            <span className="text-muted-foreground">
              Press Enter to select:
            </span>
            <div className="w-full text-5xl placeholder:text-5xl md:text-5xl h-full">
              {matches.join("")}
            </div>
          </>
        )}
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
