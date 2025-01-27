import { Link } from "react-router";
import { ChevronLeft } from "lucide-react";

export default function About() {
  return (
    <div className="">
      <Link
        to="/"
        className="inline-flex items-center gap-1 text-muted-foreground hover:text-foreground transition-colors"
      >
        <ChevronLeft className="h-4 w-4" />
        Back
      </Link>
      <h2 className="font-semibold text-xl mb-2 mt-4">About</h2>
      <p className="mb-2">
        Jaime is a Japanese IME (Input Method Editor) engine focusing on romaji
        to hiragana/full-width character conversion. Based on Google 日本語入力
        behavior.
      </p>
      <h3 className="font-semibold text-lg mb-2 mt-4">Dictionary</h3>
      <p className="mb-2">
        This web application uses the IPADIC dictionary for Japanese text
        conversion. IPADIC is provided under its own{" "}
        <a
          href="https://github.com/egegungordu/jaime/blob/main/dictionaries/ipadic/COPYING"
          target="_blank"
          rel="noopener noreferrer"
          className="underline text-orange-primary"
        >
          license terms
        </a>
        , developed by the Nara Institute of Science and Technology (NAIST).
      </p>
    </div>
  );
}
