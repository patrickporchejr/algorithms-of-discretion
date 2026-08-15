test_that("add_figure_caption adds a caption to a plain ggplot, styled as italic", {
  p <- ggplot2::ggplot(mtcars, ggplot2::aes(mpg, wt)) + ggplot2::geom_point()
  out <- add_figure_caption(p, "A short caption.")
  expect_equal(out$labels$caption, "A short caption.")
  expect_s3_class(out$theme$plot.caption, "element_text")
  expect_equal(out$theme$plot.caption$face, "italic")
})

test_that("add_figure_caption wraps long captions across multiple lines", {
  p <- ggplot2::ggplot(mtcars, ggplot2::aes(mpg, wt)) + ggplot2::geom_point()
  long_caption <- paste(rep("word", 40), collapse = " ")
  out <- add_figure_caption(p, long_caption, width = 40)
  expect_true(grepl("\n", out$labels$caption, fixed = TRUE))
})

test_that("add_figure_caption merges onto a patchwork object without dropping its title/subtitle", {
  skip_if_not_installed("patchwork")
  p1 <- ggplot2::ggplot(mtcars, ggplot2::aes(mpg, wt)) + ggplot2::geom_point()
  p2 <- ggplot2::ggplot(mtcars, ggplot2::aes(mpg, hp)) + ggplot2::geom_point()
  combined <- p1 + p2 + patchwork::plot_annotation(title = "T", subtitle = "S")

  out <- add_figure_caption(combined, "A finding.")
  expect_equal(out$patches$annotation$title, "T")
  expect_equal(out$patches$annotation$subtitle, "S")
  expect_equal(out$patches$annotation$caption, "A finding.")
})
