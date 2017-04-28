#ifndef DATA_H_
#define DATA_H_

#include <Rcpp.h>
#include "globals.h"

class Data {

public:
	Data();
	Data(Rcpp::IntegerMatrix& data, Rcpp::NumericVector& response);

	virtual ~Data();

	// Get the number of samples
	size_t getNumObservations();

	// Get the number of features
	size_t getNumFeatures();

	// Get outcome value of a sample
	double getOutcome(size_t sample);

	// Get feature data of a sample
	int getFeature(size_t sample, size_t feature);

protected:

	// Outcome
	Rcpp::NumericVector& outcome;

	// Independent features
	Rcpp::IntegerMatrix& data;

	// Number of observations
	size_t n_obs;

	// Number of features
	size_t n_feat;

private:
	DISALLOW_COPY_AND_ASSIGN(Data);

};

#endif /* DATA_H_ */