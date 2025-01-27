import { ThemeToggle } from "./components/ui/theme-toggle";
import { Outlet } from "react-router";
import { Github } from "lucide-react";
import { cn } from "./lib/utils";
import { Link } from "react-router";

export default function RootLayout() {
  return (
    <div className={cn("min-h-screen relative")}>
      <div className="container mx-auto py-8 pb-2 px-4 relative">
        <div className="flex flex-col min-h-[calc(100vh-2.5rem)]">
          <div className="w-full max-w-3xl mx-auto flex-1 flex flex-col gap-6">
            <div className="flex items-center justify-between">
              <Link to="/" className="text-3xl font-bold">
                Jaime
              </Link>
              <div className="flex items-center gap-2">
                <ThemeToggle />
              </div>
            </div>
            <main className="flex-1">
              <Outlet />
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
              <Link
                to="/about"
                className="hover:text-foreground transition-colors"
              >
                About
              </Link>
            </footer>
          </div>
        </div>
      </div>
    </div>
  );
}
