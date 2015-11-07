############################################################################
## Joint Modeling Oracle Reliability and Regularity in
## Large-scale Crowdsourced Affective Data
## Jianbo Ye <jxy198 at ist.psu.edu>

############################################################################
library("Matrix")
library("pracma")

## create hyperedge I_{i,j}^{(k)} within an image k
## from continous 1D dimension data
agreement_hyperedge = function (vals, cutoff = 2.0) {
  l = length(vals);
  if (l==1) return (0.);
  sqrdiff = matrix(vals*vals, l, l) + 
    matrix(vals*vals, l, l, byrow = T) - 
    2* vals %*% t(vals);
  agreemat = (sqrdiff <= cutoff*cutoff);
  diag(agreemat) = 0;
  return (agreemat);
}

crossagreement = function (vals0, vals1, trusts, cutoff=2.0) {
  l0=length(vals0);
  l1=length(vals1);
  stopifnot(length(trusts) == l1);
  if (min(l0,l1)==1) return (0.);
  sqrdiff = matrix(vals0 * vals0, l0, l1) +
            matrix(vals1 * vals1, l0, l1, byrow = T) -
            2* vals0 %*% t(vals1);
  return(((sqrdiff <= cutoff*cutoff) %*% trusts) / sum(trusts));
}

## read csv data
emodata = read.csv("filter_four.csv", 
                   header=FALSE, 
                   col.names = c("pid", "uid", "valence", "arousal", "dominance", "likeness"));
## set property of interests
ratingdata=emodata$valence;

## set the minimal score difference
ticks=0.5;

## set the minimal score
lowestbreak=0.5;

## set the maximal score
highestbreak=9;

## quantize data into histograms
histcount = hist(ratingdata, breaks=seq(lowestbreak,highestbreak,ticks));

## set number of ratings
n=length(ratingdata);

## set percentiles at each score
histcum=cumsum(c(0, histcount$counts));

## set the cutoff agreement threshold
cutoff=nrow(emodata)/5.;

## set image_count and user_count
M = max(emodata$pid);
N = max(emodata$uid);

## create raw sparse matrix data
sdata = sparseMatrix(i=emodata$pid, j=emodata$uid, x=ratingdata, 
                     dims=c(M,N));

computetrusts = function (usr_trusts, sdata) {
  ## create agreement matrix
  agreedata = sdata;
  img_trusts = as.vector((sdata != 0) %*% usr_trusts);
  rcnt = colSums(sdata != 0);
  randrate=(histcum[1:(length(histcum)-1)] + histcum[2:length(histcum)])/cutoff;
  comlist=c();
  for (i in 1:nrow(sdata)) {
    rawdata=sdata[i,,drop=TRUE];
    if (nnzero(rawdata) > 0) {
      uid=which(rawdata!=0);
      idx=(rawdata[uid]-lowestbreak)/ticks;
      withinrate=(histcum[idx]+histcum[idx+1])/cutoff;
      I=agreement_hyperedge(withinrate);
      rawdata=(I %*% usr_trusts[uid]) / colSums(I);
      comlist=c(comlist, 
                sum(crossagreement(randrate, withinrate, usr_trusts[uid]) * histcount$counts) /
                sum(histcount$counts));
      agreedata[i, uid] = rawdata;
    }
  }
  #usrprof=colSums(sdata)/rcnt;
  usrprof=as.vector((img_trusts %*% agreedata) / (img_trusts %*% (sdata != 0)));
  #randtrust = mean(comlist)
  randtrust = sum(comlist * img_trusts[which(img_trusts>0)]) / sum(img_trusts);
  return(list("usr" = usrprof, "rand" = randtrust))
}



create_agreement_hypergraph = function (sparse_ordinal_data, cutoff) {
  n = sum(rowSums(sdata != 0) > 0);
  I = list(n);
  U = list(n);
  incr=0;
  for (i in 1:nrow(sdata)) {
    rawdata=sdata[i,,drop=TRUE];
    if (nnzero(rawdata) > 0) {
      incr = incr+1;
      uid=which(rawdata!=0);
      idx=(rawdata[uid]-lowestbreak)/ticks;
      withinrate=(histcum[idx]+histcum[idx+1])/cutoff;
      I[[incr]]=agreement_hyperedge(withinrate);
      U[[incr]]=uid;
    }
  }
  return(list("I" =I, "U" =U));
}

hypergraph = create_agreement_hypergraph(sdata, cutoff);

## EM-like algorithm
simpleEM = function () {
  result=computetrusts(rep(1,N), sdata);
  for (iter in 1:10) {
    result_new=computetrusts(result$usr, sdata);
    change=abs(result$usr - result_new$usr);
    print(sum(change[which(change > 0)]));
    result = result_new;
  }
  return(result)
}

# result=simpleEM();

## draw trustability population
plotdata = function (res) {
  usrprof=res$usr;
  randtrust=res$rand;

  plot(density(usrprof[which(usrprof>0)], adjust=2), xlim=c(0,1),col='blue',
      main = "Density of Trustabilities between Random and Human",
      xlab = "Trustability");
  abline(v=randtrust, col = "blue", lwd = 2);
}

plotdata(result);

## calculate most trustable images
imgtrusts=as.vector((sdata != 0) %*% result$usr);
labeled=which(imgtrusts > 0);
avgscores=as.vector(sdata %*% result$usr) / as.vector((sdata != 0) %*% result$usr);
#avgscores=as.vector(rowSums(sdata)) / as.vector(rowSums(sdata != 0));
plot(density(imgtrusts[labeled], adjust = 1, na.rm = TRUE), xlab = "Cum. Trustability", main = "Image Trustabilities")
abline(v=result$rand * 4, col = "blue", lwd = 2);
#plot(density(avgscores[labeled], adjust = 2, na.rm = TRUE))


## plot trustability vs. avg scores
df = data.frame(x=rnorm(length(labeled)),y=rnorm(length(labeled)));
ggplot(df,aes(x=imgtrusts[labeled],y=avgscores[labeled]))+stat_density2d(aes(alpha=..level..), geom="polygon") +xlab("Trustability") +ylab("AvgScore")

## print top img sorted by trustability
sorted = sort.int( (avgscores), decreasing = TRUE , index.return = TRUE)
#write(labeled[sorted$ix[1:1000]], file="arousal_high.txt", ncolumns=1)
sorted = sort.int( (highestbreak+1 - avgscores), decreasing = TRUE , index.return = TRUE)
#write(labeled[sorted$ix[1:1000]], file="arousal_low.txt", ncolumns=1)


