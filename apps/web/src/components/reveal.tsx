"use client";

import { motion, useReducedMotion } from "motion/react";

// Signature curve for the whole site: calm, decisive deceleration.
const ease = [0.2, 0, 0, 1] as const;

/** Fades content up into place once, when it scrolls into view. */
export function Reveal({
  children,
  delay = 0,
  className,
  as = "div",
}: {
  children: React.ReactNode;
  delay?: number;
  className?: string;
  as?: "div" | "li";
}) {
  const reducedMotion = useReducedMotion();
  const Tag = as === "li" ? motion.li : motion.div;
  return (
    <Tag
      className={className}
      initial={{ opacity: 0.85, y: 20 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "0px 0px -10% 0px" }}
      transition={{ duration: reducedMotion ? 0 : 0.55, ease, delay: reducedMotion ? 0 : delay }}
    >
      {children}
    </Tag>
  );
}

/** Hero entrance: runs on load rather than on scroll. */
export function Entrance({
  children,
  delay = 0,
  className,
  scale = false,
}: {
  children: React.ReactNode;
  delay?: number;
  className?: string;
  scale?: boolean;
}) {
  const reducedMotion = useReducedMotion();
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0.85, y: scale ? 0 : 12, scale: scale ? 0.97 : 1 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      transition={{ duration: reducedMotion ? 0 : scale ? 0.7 : 0.45, ease, delay: reducedMotion ? 0 : delay }}
    >
      {children}
    </motion.div>
  );
}
