#!/usr/bin/env Rscript
library(TwoSampleMR)
library(tidyverse)
library(data.table)
library(GagnonMR)
library(ckbplotr)
library(ggforestplot)
library(ggforce)
library(scales)
library(ComplexUpset)
library(survival)
library(cowplot)
library(bplot)

setwd("/home/gagelo01/workspace/Projects/small_MR_exploration/Triglycerides_dis/")
resmvmr <- readRDS( "Data/Modified/res_mvmr.rds")
res_univariable <- fread("Data/Modified/res_univariate.txt")
res_univariable <- res_univariable[!(method  %in% c("Robust adjusted profile score (RAPS)", "Weighted mode")), ]
rescox <- fread( "Data/Modified/coxHR.txt")
corrmat<-readRDS("Data/Modified/correlationmatrix.rds")
causals<- readRDS("Data/Modified/causals.rds")
list_exp_multi <- readRDS("Data/Modified/list_exp_multi.rds")
expunisign <- readRDS("Data/Modified/expunisign.rds")
dat <- fread("Data/Modified/observationalfulldata.txt")
trad <- fread( "Data/Modified/trad")
ao <- fread("/mnt/sda/gagelo01/Vcffile/available_outcomes_2021-10-13.txt")
ao_small <- ao[id %in% list.files("/mnt/sda/gagelo01/Vcffile/MRBase_vcf/"), ]

#set theme for all ggplot plots
# old <- theme_set(theme(text = element_text(family = "arial")))

#####
##Fig 1
###huge fig 1
nonratioid<-trad$id

#rescox
rescox<- merge(rescox, trad , by.x = "exposure", by.y = "id")
rescox <- rescox[exposure %in% nonratioid,]
rescox <- rescox[order(-HR),]
rescox <- rescox[cov_inc == "+ age_enrollment + eth + sex + med + smoking + alcohol + townsend + WC", ]
rescox[, panel:= paste0("Observational", toupper(gsub("+ age_enrollment + eth + sex + med + smoking + alcohol + townsend + WC", "", cov_inc, fixed = TRUE)))]
rescox[, panel := sub("+", "with", panel, fixed = TRUE)]
#res_univariable
uni<-res_univariable[(outcome %in% c("NAFLD", "Fat_Liver") | exposure == "Fat_Liver") & method == "Inverse variance weighted", ]
uni[,panel := "Univariable MR"]
#resmvmr
multi <- lapply(resmvmr, function(x)
  x[, correctedfor := apply(.SD, 1,function(x) paste(setdiff(unique(exposure), x), collapse = "+")), .SDcols = "exposure"])
multi<-rbindlist(multi)
multi <- multi[outcome == "NAFLD" & method == "Multivariable IVW",]
multi[, panel := paste0("Multivariable MR with ", correctfor %>% gsub("UKB-b-9405", "WC", . )
                        %>% gsub("logTG_GLGC_2022", "TG", . ) %>%
                          gsub("HDL_GLGC_2022", "HDL", .))]
#rbind and format multiuni
multi_uni<- rbind(uni, multi, fill = TRUE)
multi_uni[, exposure := gsub("met-d-","", exposure)]
multi_uni[,HR:=exp(b)]
multi_uni[, lci := exp(lci)]
multi_uni[, uci := exp(uci)]
multi_uni <-multi_uni[,.(exposure, outcome, HR, lci, uci, pval, panel)]

######
data <- rbindlist(list(rescox, multi_uni), fill = TRUE)
data<-data[,.(exposure, outcome, HR, lci, uci, pval, panel)]
data[,outcome:= tolower(outcome)]
data<- merge(data, trad[,.(id, trait)], by.x = "exposure", by.y = "id", all.x = TRUE)
data <- data[exposure %in% c(nonratioid, "Fat_Liver"),]
data[,b := log(HR)]
data[,uci:=log(uci)]
data[,lci:=log(lci)]
data[,se := (uci-b)/1.96]

dt<-distinct(data[,.(exposure,trait)]) %>% as.data.table
dt[exposure %in% c("ApoA1", "ApoB"), category := "Apolipoproteins"]
dt[exposure %in% c("Acetate", "Acetoacetate", "bOHbutyrate", "Acetone"), category := "Beta-oxydation"]
dt[trait %in% c("Glucose", "Lactate", "Pyruvate", "Citrate", "Glycerol"), category := "Glycolysis and gluconeogenesis"]
dt[trait %in% c("Alanine", "Glutamine", "Glycine", "Histidine", "Isoleucine",
                "Leucine", "Valine", "Phenylalanine", "Tyrosine",
                "Total concentration of branched-chain amino acids (leucine + isoleucine + valine)"), category:="Amino Acids"]
dt[exposure %in% "GlycA", category := "Inflammation"]
dt[grepl("fatty acids", tolower(trait)) | trait %in% c("Docosahexaenoic acid", "Linoleic acid",
                                                       "Ratio of polyunsaturated fatty acids to total fatty acids") , category := "Fatty acids"]
dt[grepl("Triglycerides in ", trait) | trait %in% c("Total triglycerides"), category := "Triglycerides in"]
dt[grepl("diameter", tolower(trait)), category := "Particle diameter"]
dt[grepl("Cholesterol in", trait) | trait %in%
     c("Total cholesterol","Total free cholesterol", "Total esterified cholesterol",
       "Remnant cholesterol (non-HDL, non-LDL -cholesterol)"), category := "Cholesterol in"]
dt[grepl("Concentration of",trait), category := "Particle concentration"]
dt[trait %in% c("Albumin", "Creatinine"), category := "Fluid balance"]
dt[trait %in% c("Total cholines", "Sphingomyelins", "Phosphoglycerides", "Phosphatidylcholines"), category := "Other lipids"]
dt[trait %in% "Degree of unsaturation", category := "Fatty acids"]
dt[category == "Fatty acids", trait := gsub(" fatty acids", "", trait)]
dt<- dt[(category %in% c("Triglycerides in", "Particle concentration") & !grepl("large|small|medium|Total", trait)), category := "" ]
dt[trait %in% paste0("Concentration of ", c("VLDL", "HDL", "LDL"), " particles"), category := "Particle concentration"]
dt[category == "Triglycerides in", trait := gsub("Triglycerides in ", "", trait)]
dt[category == "Cholesterol in", trait := gsub("Cholesterol in ", "", trait)]
dt[grepl("branched-chain amino acids", trait), trait := "branched-chain amino acids"]
dt[ , category := factor(category, levels = unique(category))]
#order
dt[, density := trait %>% ifelse(grepl("VLDL", .), 1, .) %>%
     ifelse(grepl("LDL", .), 2, .)  %>% ifelse(grepl("IDL",.), 3, . ) %>% ifelse(grepl("HDL", . ), 4, .) ]
dt[, size := trait %>% ifelse(grepl("chylomicrons", .), 1, .) %>%
     ifelse(grepl("very large", .), 2, .)  %>% ifelse(grepl("large",.), 3, . ) %>% ifelse(grepl("medium", . ), 4, .) %>%
     ifelse(grepl("small", . ), 5, .)%>% ifelse(grepl("total",tolower(.)), 6, . )]
col<-c("density", "size")
dt[, (col) := lapply(.SD, as.numeric), .SDcols = col]
dt[,density:=10*density]
dt[is.na(size), size := 0]
dt[,colorder:=density + size]
dt[, typefig := as.character(category) %>%
     ifelse(. %in% c("Beta-oxydation", "Amino Acids", "Glycolysis and gluconeogenesis", "Fluid balance", "Inflammation"), "Metabolites", .) %>%
     ifelse(. %in% c("Apolipoproteins", "Other lipids", "Fatty acids"), "Lipids", .) %>%
     ifelse(. %in% c("Particle diameter", "Cholesterol in", "Particle concentration", "Triglycerides in"), "Lipoproteins", .)]
dt[,trait:=gsub(" particles|Concentration of ", "", trait)]
dt<- dt[grepl("medium|very large|very small", trait), category := "" ]
dt[, trait := gsub(" (non-HDL, non-LDL -cholesterol)", "", trait, fixed = TRUE)]
dt[, trait := gsub("Ratio of polyunsaturated to total", "PUFA/total FA", trait)]
dt[category == "Particle concentration" & trait %in% c("VLDL", "LDL", "HDL"), trait := paste0("Total ", trait)]
data[,trait:=NULL]
data <- merge(data,dt,by="exposure")
data <- data[order(typefig, category, colorder)]
data<- data[!(exposure %in% "Fat_Liver"),]

fwrite(data, "Data/Modified/nmrcoxmr.txt")

#####twopanel####
typeinc<- c("Observational", "Univariable MR")#c("cox", "cox with WC", "UVMR", "MVMR with WC")
forfig1<-data[panel %in% typeinc,]
forfig1 <- forfig1[outcome == "nafld", ]
forfig1<- forfig1[!is.na(category),]
forfig1 <- forfig1[category != "",]
forfig1[,panel := factor(panel, levels = typeinc)]
forfig1[, signif := ifelse(exposure %in% gsub("met-d-","", causals), TRUE, FALSE)]
make_forest_plot_wrapper <- function( data,
                                      col.right.heading = list("HR (95% CI)", "OR (95% CI)"),
                                      metabolic_factors = NULL,
                                      exponentiate = TRUE,
                                      xlab = "") {
  metabolic_factors<-NULL
  list_dat <- split(data, data$panel)
  list_results <- map(list_dat, function(doA) data.frame(variable = as.character(1:nrow(doA)),
                                                         estimate = round(doA$b, digits =2),
                                                         lci =  round(doA$lci, digits = 2),
                                                         uci =  round(doA$uci, digits = 2),
                                                         colour = ifelse(doA$signif, "red", "black"),
                                                         P_value = formatC(doA$pval, format = "e", digits = 1)))

  mylabels <- data.frame(heading1 = as.character(list_dat[[1]]$category),
                         heading2 = as.character(list_dat[[1]]$trait),
                         heading3 = as.character(NA),
                         variable = as.character(1:nrow(list_dat[[1]])))

  k<-make_forest_plot(panels = list_results,
                      col.key = "variable",
                      row.labels = mylabels,
                      exponentiate = exponentiate,
                      pointsize = 2,
                      rows = unique(mylabels$heading1),
                      col.stderr = NULL,
                      col.lci = "lci",
                      col.uci = "uci",
                      col.right.heading = col.right.heading,
                      xlab = xlab,#"NAFLD risk per 1 SD \n higher metabolomic measure",
                      blankrows = c(0,1,0,0),
                      colour = "colour", #"colour"
                      col.right.hjust = 1,
                      panel.headings = levels(data$panel),
                      scalepoints = FALSE,
                      envir = environment(),
                      cicolour = "grey50",
                      shape = 22,
                      ciunder = TRUE,
                      stroke = 0,
                      nullval = ifelse(exponentiate == TRUE, 1, 0))
  k
  return(k)
}

wrapper_forest<- function(data, col.right.heading = NULL, metabolic_factors, xlab = "") {
k <- forestplot(
  df = data,
  name = trait,
  se = se,
  estimate = b,
  pvalue = pval,
  psignif = 0.05,
  xlab = xlab,#paste0("NAFLD risk per 1 SD increase in circulating ", metabolic_factors),
  logodds = TRUE,
  # colour = signif,
  ci = 0.95,
  # colour = panel,
  # xlim = data[, round(c(min(exp(b))-0.1,max(exp(b))+0.1), digits = 1)]
  # xlim = data[, round(c(min(exp(lci)),max(exp(uci))), digits = 1)]
  xlim = c(0.5,2)
)

k <- k+ facet_grid(facets = category ~ panel, scales = "free_y", space = "free",
                   shrink = TRUE,
                   labeller = "label_value",
                   drop = TRUE) +
  theme(strip.text.y.right = element_text(angle = 0),
        legend.position="none") +
  scale_x_continuous(breaks = c(0.6,0.8, 1,1.2, 1.6,2,3))
k <- k +
  theme(panel.background=element_blank(),
        axis.line=element_line(),
        axis.title.y=element_blank(),
        strip.background=element_blank(),
        strip.text=element_text(face="bold"),
        panel.grid.major.y=element_line(color=c("white", "gray90"), linewidth=8),
        panel.grid.major.x=element_line(linetype="42424242", color="gray80"))
k
return(k)
}

savemyplot<-function(dat,
                     metabolic_factors = c("Metabolites", "Lipids","Lipoproteins"),
                     method_to_forest = "make_forest_plot_wrapper", #"make_forest_plot_wrapper" #wrapper_forest)
                     exponentiate = TRUE,
                     figname = "Figure", #"SupplementaryFigure"
                     fignum = 0,
                     device = "tiff",
                     col.right.heading = list("HR (95% CI)", "OR (95% CI)"),
                     xlab = "") {

  if(method_to_forest=="make_forest_plot_wrapper"){col.right.heading<-col.right.heading}else{col.right.heading<-NULL}
  for(i in 1:length(metabolic_factors)) {
    datsmall<-dat[typefig == metabolic_factors[i],]
    k<-get(method_to_forest)(data = datsmall,
                             metabolic_factors = tolower(metabolic_factors[i]),
                             col.right.heading = col.right.heading,
                             xlab = xlab)
    if(!("ggplot"%in%class(k))){k<-k$plot}
    ggsave(paste0("Results/", figname, i+fignum, ".", device),plot = k,
           width=724/72,
           height=datsmall[, (length(unique(exposure))+2*length(unique(category)))*15]/72,
           units="in", scale=1, dpi = 500,
           device = device)
    saveRDS(object = k, file = paste0("Results/", "SupplementaryFigure", i, ".rds"))
  }
}

metabolic_factors <- c("Metabolites", "Lipids","Lipoproteins")
method_to_forest<- "make_forest_plot_wrapper" #"make_forest_plot_wrapper" #wrapper_forest
device = "tiff"
savemyplot(dat = forfig1, metabolic_factors = metabolic_factors,
           method_to_forest = method_to_forest, device = device,
           xlab = "Effect on NAFLD")


#####correlation matrix#####
#correlation matrix
tmp<-corrmat
tmp <- tmp[gsub("met-d-", "", causals), gsub("met-d-", "", causals)]
mat_cor <- tmp[gsub("met-d-", "", causals), gsub("met-d-", "", causals)]
{col <- colorRampPalette(c("#67001F", "#B2182B", "#D6604D",
                           "#F4A582", "#FDDBC7", "#FFFFFF", "#D1E5F0", "#92C5DE",
                           "#4393C3", "#2166AC", "#053061"))(200)
  col<-rev(col)
  heatmap(mat_cor, col=col, symm=TRUE)}

levels <- colnames(mat_cor)
heat <- as.data.frame(mat_cor)
heat$row <- rownames(heat)
rownames(heat)<-NULL
setDT(heat)
heat <- melt(heat, id.vars = "row")
# heat[,row:=factor(row, levels = rev(levels))]
# heat[,variable:=factor(variable, levels = rev(levels))]

otter_dendro <- as.dendrogram(hclust(d = dist(x = mat_cor)))
otter_order <- order.dendrogram(otter_dendro)

heat[,row:=factor(row, levels = row[otter_order], ordered = TRUE)]
heat[,variable:=factor(variable, levels = row[otter_order], ordered = TRUE)]



k <- ggplot(data = heat, aes(x = variable, y = row, fill = value))  +
  geom_tile() +
  scale_fill_gradientn(
    colors=c("#5884E5","white","#9E131E"),
    values=scales::rescale(c(-1,0,1)),
    limits=c(-1,1)
  ) +
  theme(axis.text.x = element_text(angle = 60,hjust = 1,colour = "gray20"),
        panel.background = element_blank(),
        legend.position = "right",
        legend.text = element_text(color = "gray20"),
        axis.title = element_blank()
  ) +
  labs(fill = "")

ggsave(paste0("Results/", "SupplementaryFigure7", ".tiff"), plot = k,
       width=700/72,height=600/72, units="in", scale=1, dpi = 500,
       device = "tiff")
saveRDS(object = k, file = paste0("Results/", "SupplementaryFigure7", ".rds"))
#Supplementary figure 1
# typeinc<-  c("cox with WC", "cox with TG", "cox with HDL", "cox with WC + TG + HDL",
# "MVMR with WC", "MVMR with TG", "MVMR with HDL", "MVMR with WC + TG + HDL")
typeinc<-  c("Univariable MR", "Multivariable MR with WC")
forsupfig2<-data[panel %in% typeinc,]
forsupfig2<- forsupfig2[!is.na(category),]
forsupfig2<- forsupfig2[outcome=="nafld",]
forsupfig2 <- forsupfig2[category != "",]
forsupfig2[,panel := factor(panel, levels = typeinc)]
forsupfig2[, signif := ifelse(exposure %in% gsub("met-d-","", causals), TRUE, FALSE)]

savemyplot(dat = forsupfig2,
           metabolic_factors = metabolic_factors,
           method_to_forest = method_to_forest,
           exponentiate = TRUE,
           figname = "SupplementaryFigure",
           fignum = 0,
           device = device,
           col.right.heading = list("OR (95% CI)","OR (95% CI)"))

####
#####Supplementary figure 2####
typeinc<-  c("Univariable MR")
forsupfig3<-data[panel %in% typeinc,]
forsupfig3[,outcome:=gsub("met-d-", "", outcome)]
forsupfig3[,exposure:=tolower(exposure)]
forsupfig3<- forsupfig3[(exposure == "fat_liver" & outcome %in% tolower(nonratioid)) | (outcome == "fat_liver" & exposure %in% tolower(nonratioid)),]
forsupfig3[,panel := ifelse(exposure == "fat_liver", "liver_fat_as_exposure", "liver_fat_as_outcome")%>% as.factor]
forsupfig3[, signif := FALSE]
# forsupfig3 <- forsupfig3[category != "",]
forsupfig3[panel == "liver_fat_as_exposure", todump := outcome]
forsupfig3[panel == "liver_fat_as_exposure", outcome := exposure]
forsupfig3[panel == "liver_fat_as_exposure", exposure := todump]
forsupfig3[,c("trait", "todump", "category","typefig", "density", "size", "colorder") := NULL]
dt[,exp:=tolower(exposure)]
forsupfig3<-merge(forsupfig3, dt , by.x = "exposure", by.y = "exp")
forsupfig3<-forsupfig3[category != "", ]
forsupfig3 <- forsupfig3[order(typefig, category, colorder)]

savemyplot(dat = forsupfig3,
           metabolic_factors = metabolic_factors,
           method_to_forest = method_to_forest,
           exponentiate = FALSE,
           figname = "SupplementaryFigure",
           fignum = 3,
           device = device,
           col.right.heading = list("Effect (95% CI)","Effect (95% CI)"))



#Figure4

#Kaplein meir curve for tg
# ntile_format <- function(x, n, unitchr = "mmol/L") {
#   var_quantile <- dplyr::ntile(x = x, n = n)
#   k<-stats::quantile(x=x, probs = seq(0, 1, 1/n), na.rm = TRUE)
#   dttranslate<-data.table(var_quantile = 1:n, var_quantile_long = as.character(NA))
#   for(i in 1:(length(k)-1)) {
#     dttranslate[i, ]$var_quantile_long <- paste0("Quintile ", i, "\n (",round(k[i], digits = 2),", ", round(k[i+1], digits = 2),")", unitchr)
#   }
#
#   toto <- merge(data.table(var_quantile = var_quantile, roworder = 1:length(var_quantile)), dttranslate, by = "var_quantile", all = TRUE)
#   return(toto[order(roworder)]$var_quantile_long)
# }
#
# dt<-dat[!(!is.na(nafld_date) & f.53.0.0 > nafld_date),]
# vecindex<- 5#c(2,3,4,5,10)
# var<-c(Triglycerides = "tg", `HDL cholesterol` = "hdl")
# list_plot <- vector(mode = "list", length = length(var))
# for(i in seq_along(var)) {
#   dt[,var_quintile:=ntile_format(x = get(var[i]),n = vecindex)%>%as.factor(.)]
#   fit<-survival::survfit(Surv(nafld_time/365.25, nafld_censored) ~ var_quintile, data=dt)
#   k <- survminer::ggsurvplot(fit, data = dt, ylim = c(0.95,1), censor.size = 0.2,size = 0.5,legend = "right",
#                              legend.title = names(var)[i], xlab = "Follow-up (Years)", ylab = "Diagnosis-free survival",
#                              font.legend = 12, legend.labs = levels(dt$var_quintile))
# list_plot[[i]] <- k$plot  + theme(legend.position="right")
# }
#
# ggarrange(list_plot[[1]], list_plot[[2]],
#           labels = c("A)", "B)"),
#           ncol = 1, nrow = 2)
#
# ggsave(file = paste0("Results/Figure4.tiff"),
#          width=524/72,height=524/72, units="in", scale=1,
#          device = "tiff")


####Figure 5####

# mvmr_object <- list("logTG_GLGC_2022 + UKB-b-9405 ~ NAFLD correctfor = NULL (pval=5e-08)")
# file_name <- c("Figure4")
# for(i in 1:length(file_name)) {
#   mvmr_results <- lapply(as.list(mvmr_object[[i]]), function(x) resmvmr[[x]]) %>% rbindlist(.)
#
#   # k  <- gsub("-and-|-on-", ",", mvmr_object[[i]])
#   # k <- strsplit(k, split = ",")   %>% unlist
#   # uni <- res_univariate[exposure %in% k[1:2] & outcome == k[3], ]
#   uni <- res_univariable[exposure %in% mvmr_results$exposure & outcome %in% mvmr_results$outcome, ]
#   mvmr_results <-  mvmr_results[clump_exposure=="none", ]
#   mvmr_results <- rbindlist(list(uni, mvmr_results), fill = TRUE)
#
#   unimeth<-"Inverse variance weighted"
#   multimeth<- c("Multivariable IVW", "Multivariable Median",
#                 "Multivariable Lasso", "Multivariable Egger")
#
#   data <- mvmr_results[method %in% c(unimeth, multimeth),]
#   data[, Category_other := ifelse(method %in% unimeth, "Univariable", "Multivariable")]
#   data[, Category_other := factor(Category_other, levels = c("Univariable", "Multivariable"))]
#   data[,name := gsub("UKB-b-9405", "Waist circumference", exposure) %>% gsub("logTG_GLGC_2022", "Triglycerides", .)]
#   data[, outcome := factor(outcome, levels = c("NAFLD", "Fat_Liver"))]
#   data<-data[order(Category_other,exposure,outcome)]
#
#   forestplot(
#     df = data,
#     name = name,
#     se = se,
#     estimate = b,
#     pvalue = pval,
#     psignif = 0.05,
#     xlab = "Effect of 1 SD increase in WC/TG on NAFLD risk (OR)",
#     ci = 0.95,
#     colour = method,
#     logodds = TRUE
#   ) +
#     theme(text = element_text(linewidth = 10)) +
#     theme(legend.position="right") +
#     ggforce::facet_col(
#       # facets = ~outcome_category,
#       facets = ~Category_other,
#       scales = "free_y",
#       space = "free"
#     )
#
#
#   ggsave(paste0("Results/", "Figure5", ".tiff"),
#          width=350/72,height=250/72, units="in", scale=1,
#          device = "tiff")
# }


#####Supplementary figure volcano plot#####
nmrcoxmr <- fread("Data/Modified/nmrcoxmr.txt")
pcares <- readRDS("Data/Modified/pcares.rds")
ntest <- min(which(pcares@R2cum > 0.9))

volcano <- nmrcoxmr[outcome=="nafld" & exposure %in% trad$id, ]
volcano[, diffexpressed := "NS"]
volcano[, diffexpressed := diffexpressed %>% ifelse(b > 0 & pval < 0.05/ntest, "Associated with higher NAFLD risk", .) %>%
          ifelse(b < 0 & pval < 0.05/ntest,  "Associated with lower NAFLD risk", .)]
volcano[, diffexpressed := factor(diffexpressed, levels = c("Associated with higher NAFLD risk","Associated with lower NAFLD risk", "NS"))]

volcano[exposure %in% c("Acetate","PUFA_pct","HDL_C","Total_TG"), delabel := trait]
volcano<-volcano[panel%in%c("Observational","Univariable MR"), ]
volcano[, logpval := -log10(pval)]
  plot_volcano <- function(volcano,
                           xlab = "Effect on BMI (Beta)",
                           lim = 1,
                           aes_x = "b",
                           vline_value = 0) {

  # lim_y1 <- mean(volcano$logpval) * 5 * sd(volcano$logpval)
  # lim_y2 <- max(volcano[!is.na(delabel),]$logpval)
  # lim_y <- max(c(lim_y1, lim_y2))

  lim_y <- max(volcano$logpval)
  volcanoplot <-  ggplot(data = volcano, aes(x = get(aes_x), y = logpval, col = diffexpressed,  label=delabel)) +
    geom_point(size = 1, alpha = ifelse(volcano[, is.na(delabel)], 0.5, 1)) +
    theme_bw() +
    scale_color_manual(values=c("#5884E5","#9E131E", "#B0B0B0")) +
    facet_grid(panel~. , scales = "free") +
    geom_hline(  yintercept = -log10(0.05/ntest), color = "#A40606", linewidth = 1) +
    ggrepel::geom_text_repel(
      force = 5,
      force_pull = 1,
      box.padding = 0.4,
      max.iter = 1e7,
      show.legend = F,
      text.size = 1.5,
      linewidth = 3.5,
      segment.size = 0.5,
      segment.alpha = 0.5,
      segment.linetype = "solid",
      min.segment.length = 0,
      max.overlaps = nrow(volcano[!is.na(delabel), ]) +10
    ) +
    labs(x = xlab, y = expression(-Log[10](P))) +
    theme(    panel.grid.major.y = element_line(linewidth = 0.5, colour = "gray60"),
              panel.grid.major.x = element_blank(),
              panel.grid.minor.y = element_blank(),
              panel.grid.minor.x = element_blank(),
              panel.background = element_blank(),
              plot.margin = margin(t = 0.5, r = 0.5, b = 0.5, l = 0.5, "cm"),
              legend.position = "top",
              legend.title = element_blank(),
              # axis.title = element_text(size = 25, colour = "gray20"),
              axis.line = element_line(size = 1, colour = "gray20"),
              axis.ticks = element_line(size = 1, colour = "gray20"),
              axis.ticks.length = unit(.25, "cm"),
              legend.text = element_text(
                color = "gray20",
                size = 10,
                margin = margin(l = 0.2, r = 0.2))) +
    geom_vline(xintercept = vline_value, lty = 2)

  return(volcanoplot)
}

volcanoplot <- plot_volcano(volcano = volcano,
                            xlab = "Association with NAFLD (HR or OR)",
                            lim = 1,
                            aes_x = "HR",
                            vline_value = 1)
volcanoplot
ggsave(plot = volcanoplot, filename = "Results/Figure6.tiff", dpi = 300,
       width = 652/72,height = 585/72,units="in",scale=1, device = "tiff")

message("This script finished without errors")
