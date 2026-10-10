import Image from "next/image";
import { Volume2Icon } from "lucide-react";

const stories = [
  {
    label: "Point & click", image: "feature-pointer-2d",
    alt: "A finger swiping on a phone trackpad beside a large pointer arrow",
    title: "Get comfortable. Stay in control.",
    body: "Tap your Mac's desktop directly, or use your phone as a trackpad. Scroll, zoom, and move around your familiar apps.",
    detail: "Touch, trackpad, and gestures",
  },
  {
    label: "Type & shortcuts", image: "feature-shortcuts-2d",
    alt: "Flat illustrated Command, Shift, C, and V keyboard keys",
    title: "A keyboard within reach.",
    body: "Reply to a message or take a quick note. Use your phone's keyboard and dictation, along with the Mac shortcuts you know.",
    detail: "Command, Option, Control, and function keys",
  },
  {
    label: "Send & receive", image: "feature-transfer-2d",
    alt: "Two illustrated folders exchanging a document with an approval check",
    title: "Pass the little things along.",
    body: "Share clipboard text when you ask for it. Send a file in either direction, with the receiving device choosing whether to accept it.",
    detail: "Your clipboard and files, on your terms",
  },
];

export function FeatureStories() {
  return (
    <>
      <div className="feature-stories">
        {stories.map((story, index) => (
          <article className="feature-story" key={story.image}>
            <div className="story-art">
              <Image src={`/illustrations/${story.image}.webp`} alt={story.alt} width={720} height={720} sizes="(min-width: 1024px) 370px, (min-width: 769px) 30vw, 90vw" />
            </div>
            <p className="story-label"><span aria-hidden>0{index + 1}</span>{story.label}</p>
            <h3>{story.title}</h3>
            <p className="story-description">{story.body}</p>
            <p className="story-detail">{story.detail}</p>
          </article>
        ))}
      </div>
      <p className="story-audio"><Volume2Icon className="size-4" aria-hidden />Your Mac&apos;s audio can come along, too.</p>
    </>
  );
}
